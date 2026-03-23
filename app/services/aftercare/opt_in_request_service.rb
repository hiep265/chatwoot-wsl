module Aftercare
  class OptInRequestService
    class GmailDeliveryUnavailableError < StandardError
      attr_reader :capability_status, :payload

      def initialize(message, capability_status:, payload: {})
        @capability_status = capability_status
        @payload = payload
        super(message)
      end
    end

    def initialize(subscription:, actor: nil)
      @subscription = subscription
      @enrollment = subscription.aftercare_enrollment
      @actor = actor
    end

    def perform
      request_time = Time.current
      ensure_gmail_delivery_ready!

      @subscription.update!(
        provider: 'gmail',
        requested_at: request_time,
        capability_status: 'supported',
        last_error: nil
      )

      result = Aftercare::OptInWebhookIngestService.new(
        subscription: @subscription,
        event_name: 'opt_in.subscribed',
        occurred_at: request_time.iso8601,
        payload: {
          source: 'gmail_delivery_ready',
          topic: @subscription.topic,
          delivery_email: delivery_email
        }
      ).perform

      AuditService.record!(
        account: @enrollment.account,
        enrollment: @enrollment,
        actor: @actor,
        event_type: 'aftercare_gmail_delivery_ready',
        payload: {
          subscription_id: @subscription.id,
          topic: @subscription.topic,
          delivery_email: delivery_email
        }
      )

      result[:subscription]
    rescue StandardError => e
      persist_request_failure!(e)
      raise
    end

    private

    def ensure_gmail_delivery_ready!
      raise GmailDeliveryUnavailableError.new(
        'Contact email is required before aftercare can send via Gmail',
        capability_status: 'email_missing',
        payload: { contact_id: @enrollment.contact_id }
      ) if delivery_email.blank?

      return if Aftercare::GmailDeliveryCapability.smtp_ready?

      raise GmailDeliveryUnavailableError.new(
        'SMTP is not configured for Gmail aftercare delivery',
        capability_status: 'smtp_not_configured',
        payload: { account_id: @enrollment.account_id }
      )
    end

    def delivery_email
      @delivery_email ||= @enrollment.contact.email.to_s.strip.presence
    end

    def persist_request_failure!(error)
      safe_message = error.message.to_s.strip.presence || 'Gmail delivery is not ready'
      classification = classify_request_failure(error)

      subscription_attributes = {
        provider: 'gmail',
        last_error: safe_message
      }
      subscription_attributes[:status] = classification[:subscription_status] if classification[:subscription_status]
      subscription_attributes[:capability_status] = classification[:capability_status] if classification[:capability_status]
      @subscription.update!(subscription_attributes)

      enrollment_attributes = {
        last_error: safe_message
      }
      enrollment_attributes[:status] = classification[:enrollment_status] if classification[:enrollment_status]
      @enrollment.update!(enrollment_attributes)

      AuditService.record!(
        account: @enrollment.account,
        enrollment: @enrollment,
        actor: @actor,
        event_type: 'aftercare_opt_in_request_failed',
        payload: {
          subscription_id: @subscription.id,
          topic: @subscription.topic,
          error: safe_message,
          capability_status: classification[:capability_status],
          response_payload: error.respond_to?(:payload) ? error.payload : {}
        }
      )
    end

    def classify_request_failure(error)
      case error.respond_to?(:capability_status) ? error.capability_status.to_s : nil
      when 'email_missing'
        {
          capability_status: 'email_missing',
          subscription_status: :unsupported_channel_capability,
          enrollment_status: :blocked_capability_disabled
        }
      when 'smtp_not_configured'
        {
          capability_status: 'smtp_not_configured',
          subscription_status: :unsupported_channel_capability,
          enrollment_status: :blocked_capability_disabled
        }
      else
        {}
      end
    end
  end
end
