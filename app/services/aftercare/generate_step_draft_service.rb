require 'json'
require 'net/http'

module Aftercare
  class GenerateStepDraftService
    class DraftGenerationError < StandardError; end

    RECENT_MESSAGE_LIMIT = 30

    def initialize(step:, actor: nil)
      @step = step
      @enrollment = step.aftercare_enrollment
      @actor = actor
    end

    def perform
      payload = build_payload
      mark_pending!

      response = request_draft!(payload)
      persist_success!(payload, response)
    rescue DraftGenerationError => e
      persist_failure!(payload || {}, e.message)
      raise
    rescue StandardError => e
      persist_failure!(payload || {}, e.message)
      raise DraftGenerationError, e.message
    end

    private

    def mark_pending!
      @step.update!(
        draft_status: :pending,
        draft_error: nil
      )
    end

    def request_draft!(payload)
      base_url = ChatbotlevanEndpointResolver.chatbotlevan_base_url
      raise DraftGenerationError, 'CHATBOTLEVAN_BASE_URL is not configured' if base_url.blank?

      uri = URI.parse("#{base_url}/internal/aftercare/drafts")
      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'

      token = ENV.fetch('CHATBOTLEVAN_API_TOKEN', '').to_s.strip
      request['Authorization'] = "Bearer #{token}" if token.present?
      request.body = payload.to_json

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == 'https'
      http.open_timeout = 10
      http.read_timeout = 120

      response = http.request(request)
      body = parse_json(response.body)

      unless response.code.to_i.between?(200, 299)
        detail = if body.is_a?(Hash)
                   body['detail'].presence || body['error'].presence || body.to_json
                 else
                   response.body.to_s
                 end
        raise DraftGenerationError, "chatbotlevan draft request failed: #{detail}"
      end

      draft_text = body.is_a?(Hash) ? body['draft_text'].to_s.strip : ''
      raise DraftGenerationError, 'chatbotlevan returned an empty draft_text' if draft_text.blank?

      body
    rescue JSON::ParserError => e
      raise DraftGenerationError, "chatbotlevan returned invalid JSON: #{e.message}"
    end

    def persist_success!(payload, response)
      @step.update!(
        draft_status: :ready,
        draft_body: response['draft_text'].to_s.strip,
        draft_summary: response['summary'].to_s.strip.presence,
        draft_version: response['version_fingerprint'].to_s.strip.presence,
        draft_generated_at: Time.current,
        draft_input_snapshot: payload,
        draft_error: nil,
        last_error: nil
      )

      AuditService.record!(
        account: @enrollment.account,
        enrollment: @enrollment,
        actor: @actor,
        event_type: 'aftercare_draft_generated',
        payload: {
          step_id: @step.id,
          draft_version: @step.draft_version,
          draft_status: @step.draft_status
        }
      )

      @step
    end

    def persist_failure!(payload, message)
      safe_message = message.to_s.strip.presence || 'Unknown draft generation error'

      @step.update!(
        draft_status: :failed_generation,
        draft_input_snapshot: payload,
        draft_error: safe_message,
        last_error: safe_message
      )

      AuditService.record!(
        account: @enrollment.account,
        enrollment: @enrollment,
        actor: @actor,
        event_type: 'aftercare_draft_failed',
        payload: {
          step_id: @step.id,
          draft_status: @step.draft_status,
          error: safe_message
        }
      )
    end

    def build_payload
      {
        account: {
          id: @enrollment.account_id
        },
        conversation: {
          id: @enrollment.conversation_id,
          display_id: @enrollment.conversation.display_id,
          inbox_id: @enrollment.inbox_id,
          channel_type: @enrollment.channel_type,
          channel_key: @enrollment.channel_key
        },
        contact: {
          id: @enrollment.contact_id,
          name: @enrollment.contact.name,
          email: @enrollment.contact.email,
          phone_number: @enrollment.contact.phone_number
        },
        sequence: {
          id: @enrollment.aftercare_sequence_id,
          code: @enrollment.aftercare_sequence.code,
          name: @enrollment.aftercare_sequence.name,
          description: @enrollment.aftercare_sequence.description,
          opt_in_topic: @enrollment.aftercare_sequence.opt_in_topic
        },
        enrollment: {
          id: @enrollment.id,
          status: @enrollment.status,
          staff_note: @enrollment.staff_note,
          timezone_name: @enrollment.timezone_name,
          anchor_at: @enrollment.anchor_at&.utc&.iso8601
        },
        step: {
          id: @step.id,
          position: @step.position,
          title: @step.title,
          instructions: @step.instructions,
          step_note: @step.step_note,
          scheduled_for: @step.scheduled_for&.utc&.iso8601,
          draft_status: @step.draft_status
        },
        recent_messages: recent_messages
      }
    end

    def recent_messages
      @enrollment.conversation.messages.chat
        .reorder(created_at: :desc, id: :desc)
        .limit(RECENT_MESSAGE_LIMIT)
        .to_a
        .reverse
        .map do |message|
          {
            id: message.id,
            message_type: message.message_type,
            content: message.content.to_s,
            created_at: message.created_at&.utc&.iso8601
          }
        end
    end

    def parse_json(raw_body)
      return {} if raw_body.blank?

      JSON.parse(raw_body)
    end
  end
end
