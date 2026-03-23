require 'securerandom'

module Aftercare
  class DispatchStepService
    class DispatchError < StandardError; end

    def initialize(step:, attempt_key: nil)
      @step = step
      @enrollment = step.aftercare_enrollment
      @subscription = @enrollment.aftercare_opt_in_subscription
      @attempt_key = attempt_key.presence || SecureRandom.uuid
    end

    def perform
      validate_dispatchable!
      refresh_draft_if_needed!
      delivery_decision = resolve_delivery_lane!

      dispatch_log = find_or_create_dispatch_log!(delivery_decision)
      message = nil

      ActiveRecord::Base.transaction do
        @step.update!(
          status: :sending,
          last_error: nil
        )

        message = create_outgoing_message!(delivery_decision)

        dispatch_log.update!(
          message: message,
          status: 'sending',
          provider_message_id: message.source_id,
          sent_at: nil,
          error_message: nil,
          metadata: dispatch_log.metadata.to_h.merge(dispatch_metadata(delivery_decision))
        )

        AuditService.record!(
          account: @enrollment.account,
          enrollment: @enrollment,
          actor: nil,
          event_type: 'aftercare_step_dispatched',
          payload: {
            step_id: @step.id,
            dispatch_log_id: dispatch_log.id,
            message_id: message.id
          }.merge(dispatch_metadata(delivery_decision))
        )

        @enrollment.update!(last_error: nil)
        @subscription&.update!(last_error: nil)
      end

      Aftercare::GmailDeliveryService.new(message: message).perform if delivery_decision.lane == 'gmail'

      message
    rescue StandardError => e
      persist_failure!(e)
      raise DispatchError, e.message
    end

    private

    def resolve_delivery_lane!
      Aftercare::DeliveryLaneResolver.new(enrollment: @enrollment).perform
    end

    def validate_dispatchable!
      raise DispatchError, 'Aftercare enrollment is not active' unless @enrollment.active?
      raise DispatchError, 'Aftercare step is disabled' unless @step.enabled?
      raise DispatchError, 'Aftercare step is not scheduled' unless @step.status_scheduled?
      raise DispatchError, 'Aftercare opt-in subscription is not subscribed' unless @subscription&.subscribed?
      raise DispatchError, 'Aftercare draft is blank' if @step.draft_body.to_s.strip.blank?
    end

    def refresh_draft_if_needed!
      return unless draft_refresh_needed?

      Aftercare::GenerateStepDraftService.new(
        step: @step,
        actor: @enrollment.created_by
      ).perform

      @step.reload
    rescue Aftercare::GenerateStepDraftService::DraftGenerationError => e
      raise DispatchError, e.message
    end

    def draft_refresh_needed?
      return true unless @step.draft_ready?
      return true if @step.draft_generated_at.blank?

      @enrollment.conversation.messages.chat
                 .where('created_at > ?', @step.draft_generated_at)
                 .exists?
    end

    def find_or_create_dispatch_log!(delivery_decision)
      AftercareDispatchLog.find_or_create_by!(
        aftercare_enrollment: @enrollment,
        aftercare_enrollment_step: @step,
        attempt_key: @attempt_key
      ) do |log|
        log.status = 'sending'
        log.provider = dispatch_provider(delivery_decision)
        log.metadata = dispatch_metadata(delivery_decision)
      end
    end

    def dispatch_metadata(delivery_decision)
      {
        conversation_id: @enrollment.conversation_id,
        step_id: @step.id,
        delivery_lane: delivery_decision.lane,
        dispatch_reason: delivery_decision.reason_code,
        window_expires_at: delivery_decision.window_expires_at&.utc&.iso8601,
        delivery_email: delivery_decision.delivery_email
      }.compact
    end

    def create_outgoing_message!(delivery_decision)
      Current.executed_by = @enrollment.created_by

      @enrollment.conversation.messages.create!(
        account: @enrollment.account,
        inbox: @enrollment.inbox,
        sender: nil,
        message_type: :outgoing,
        content: @step.draft_body.to_s.strip,
        content_attributes: {
          is_bot_generated: true,
          aftercare_enrollment_id: @enrollment.id,
          aftercare_step_id: @step.id,
          aftercare_delivery_lane: delivery_decision.lane,
          aftercare_opt_in_subscription_id: delivery_decision.subscription_id,
          aftercare_delivery_email: delivery_decision.delivery_email
        }.compact
      )
    ensure
      Current.executed_by = nil
    end

    def persist_failure!(error)
      safe_message = error.message.to_s.strip.presence || 'Unknown aftercare dispatch error'

      persist_delivery_block_state!(error, safe_message)

      @step.reload
      @step.update!(
        status: :failed,
        last_error: safe_message
      )

      failure_metadata = dispatch_failure_metadata(error)

      AftercareDispatchLog.find_or_create_by!(
        aftercare_enrollment: @enrollment,
        aftercare_enrollment_step: @step,
        attempt_key: @attempt_key
      ) do |log|
        log.status = 'failed'
        log.provider = failure_provider(error)
        log.error_message = safe_message
        log.metadata = failure_metadata
      end.tap do |log|
        log.update!(
          status: 'failed',
          error_message: safe_message,
          metadata: log.metadata.to_h.merge(failure_metadata)
        )
      end

      AuditService.record!(
        account: @enrollment.account,
        enrollment: @enrollment,
        actor: nil,
        event_type: 'aftercare_step_dispatch_failed',
        payload: {
          step_id: @step.id,
          error: safe_message
        }.merge(failure_metadata)
      )
    end

    def dispatch_failure_metadata(error)
      {
        conversation_id: @enrollment.conversation_id,
        step_id: @step.id,
        dispatch_reason: error.respond_to?(:reason_code) ? error.reason_code : nil
      }.compact
    end

    def persist_delivery_block_state!(error, safe_message)
      return unless error.is_a?(Aftercare::DeliveryLaneResolver::DeliveryBlockedError)

      if @subscription.present?
        subscription_attributes = {
          last_error: safe_message
        }
        subscription_attributes[:status] = error.subscription_status if error.subscription_status.present?
        subscription_attributes[:capability_status] = error.capability_status if error.capability_status.present?
        if error.subscription_status.to_s == 'expired' && @subscription.expires_at.blank?
          subscription_attributes[:expires_at] = Time.current
        end
        @subscription.update!(subscription_attributes)
      end

      enrollment_attributes = {
        last_error: safe_message
      }
      enrollment_attributes[:status] = error.enrollment_status if error.enrollment_status.present?
      @enrollment.update!(enrollment_attributes)
    end

    def dispatch_provider(delivery_decision)
      delivery_decision.lane == 'gmail' ? 'gmail' : 'meta'
    end

    def failure_provider(error)
      return 'gmail' if error.respond_to?(:reason_code) &&
                        %w[missing_contact_email smtp_not_configured].include?(error.reason_code.to_s)

      'meta'
    end
  end
end
