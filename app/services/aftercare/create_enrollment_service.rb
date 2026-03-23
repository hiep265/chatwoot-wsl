module Aftercare
  class CreateEnrollmentService
    class IneligibleError < StandardError; end

    def initialize(account:, conversation:, sequence:, created_by:, params:)
      @account = account
      @conversation = conversation
      @sequence = sequence
      @created_by = created_by
      @params = params.deep_symbolize_keys
    end

    def perform
      eligibility = EligibilityService.new(conversation: @conversation).perform
      raise IneligibleError, eligibility.reason_code unless eligibility.eligible

      enrollment = nil

      ActiveRecord::Base.transaction do
        sync_contact_email!

        enrollment = AftercareEnrollment.create!(
          account: @account,
          conversation: @conversation,
          contact: @conversation.contact,
          inbox: @conversation.inbox,
          aftercare_sequence: @sequence,
          created_by: @created_by,
          status: :pending_optin,
          channel_type: @conversation.inbox.channel_type,
          channel_key: eligibility.channel_key,
          staff_note: @params[:staff_note],
          timezone_name: normalized_timezone_name,
          anchor_at: parsed_anchor_at,
          eligibility_status: 'eligible',
          eligibility_reason: eligibility.reason_code,
          eligible_until_at: eligibility.window_expires_at,
          idempotency_key: generated_idempotency_key
        )

        cloned_steps(enrollment).each do |attributes|
          enrollment.aftercare_enrollment_steps.create!(attributes)
        end

        enrollment.create_aftercare_opt_in_subscription!(
          topic: @sequence.opt_in_topic,
          status: :not_requested,
          provider: 'gmail',
          capability_status: eligibility.capability_status
        )

        AuditService.record!(
          account: @account,
          enrollment: enrollment,
          actor: @created_by,
          event_type: 'aftercare_enrollment_created',
          payload: {
            sequence_id: @sequence.id,
            conversation_id: @conversation.id,
            channel_key: eligibility.channel_key
          }
        )
      end

      Aftercare::RequestOptInJob.perform_later(enrollment.id)
      enrollment.aftercare_enrollment_steps.where(enabled: true).find_each do |step|
        Aftercare::GenerateStepDraftJob.perform_later(step.id)
      end
      enrollment
    end

    private

    def normalized_timezone_name
      @params[:timezone_name].presence || @sequence.default_timezone || 'UTC'
    end

    def sync_contact_email!
      normalized_email = String(@params[:contact_email] || '').strip
      return if normalized_email.blank?
      return if @conversation.contact.email.to_s.strip == normalized_email

      @conversation.contact.update!(email: normalized_email)
    end

    def parsed_anchor_at
      Time.zone.parse(@params[:anchor_at].to_s)
    rescue StandardError
      Time.current
    end

    def generated_idempotency_key
      [
        @account.id,
        @conversation.id,
        @sequence.id,
        parsed_anchor_at.to_i
      ].join(':')
    end

    def step_overrides
      Array(@params[:steps]).index_by { |item| item[:position].to_i }
    end

    def cloned_steps(enrollment)
      dynamic_steps = dynamic_steps_from_payload(enrollment)
      return dynamic_steps if dynamic_steps.present?

      @sequence.aftercare_sequence_steps.order(:position, :id).map do |step|
        override = step_overrides[step.position] || {}
        scheduled_for = begin
          Time.zone.parse(override[:scheduled_for].to_s)
        rescue StandardError
          nil
        end
        scheduled_for ||= enrollment.anchor_at + step.offset_minutes.minutes

        {
          aftercare_sequence_step: step,
          position: step.position,
          title: override[:title].presence || step.title,
          instructions: override[:instructions].presence || step.instructions,
          status: :scheduled,
          draft_status: :not_requested,
          offset_minutes: step.offset_minutes,
          scheduled_for: scheduled_for,
          step_note: override[:step_note].presence,
          enabled: override.key?(:enabled) ? ActiveModel::Type::Boolean.new.cast(override[:enabled]) : step.enabled
        }
      end
    end

    def dynamic_steps_from_payload(enrollment)
      payload_steps = Array(@params[:steps])
      return [] if payload_steps.blank?

      sequence_steps_by_position = @sequence.aftercare_sequence_steps.order(:position, :id).index_by(&:position)

      payload_steps
        .map(&:deep_symbolize_keys)
        .sort_by { |item| item[:position].to_i.positive? ? item[:position].to_i : 10_000 }
        .each_with_index
        .map do |item, index|
          position = item[:position].to_i.positive? ? item[:position].to_i : (index + 1)
          sequence_step = sequence_steps_by_position[position]
          scheduled_for = begin
            Time.zone.parse(item[:scheduled_for].to_s)
          rescue StandardError
            nil
          end
          offset_minutes = item[:offset_minutes].to_i if item.key?(:offset_minutes)
          offset_minutes ||= (
            if scheduled_for.present?
              ((scheduled_for - enrollment.anchor_at) / 60.0).round
            else
              sequence_step&.offset_minutes || 0
            end
          )
          scheduled_for ||= enrollment.anchor_at + offset_minutes.minutes

          {
            aftercare_sequence_step: sequence_step,
            position: position,
            title: item[:title].presence || sequence_step&.title || "Aftercare Step #{position}",
            instructions: item[:instructions].presence || sequence_step&.instructions,
            status: :scheduled,
            draft_status: :not_requested,
            offset_minutes: offset_minutes,
            scheduled_for: scheduled_for,
            step_note: item[:step_note].presence,
            enabled: item.key?(:enabled) ? ActiveModel::Type::Boolean.new.cast(item[:enabled]) : (sequence_step&.enabled != false)
          }
        end
    end
  end
end
