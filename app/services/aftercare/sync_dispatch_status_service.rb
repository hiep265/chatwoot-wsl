module Aftercare
  class SyncDispatchStatusService
    def initialize(message:, previous_changes: {})
      @message = message
      @previous_changes = previous_changes || {}
      @dispatch_log = AftercareDispatchLog.includes(
        :aftercare_enrollment,
        :aftercare_enrollment_step
      ).find_by(message_id: message.id)
    end

    def perform
      return unless @dispatch_log
      return sync_failure! if delivery_failed?
      return sync_success! if delivery_confirmed?
    end

    private

    def delivery_failed?
      @message.failed? && @dispatch_log.status != 'failed'
    end

    def delivery_confirmed?
      return false unless @dispatch_log.status == 'sending'

      @message.delivered? || @message.read? || source_id_confirmed?
    end

    def source_id_confirmed?
      @message.source_id.present? && @previous_changes.key?('source_id')
    end

    def sync_failure!
      safe_error_message = @message.external_error.to_s.strip.presence || 'Message delivery failed'
      step = @dispatch_log.aftercare_enrollment_step
      enrollment = @dispatch_log.aftercare_enrollment

      ActiveRecord::Base.transaction do
        @dispatch_log.update!(
          status: 'failed',
          provider_message_id: @message.source_id,
          error_message: safe_error_message,
          sent_at: nil
        )

        unless step.status_cancelled?
          step.update!(
            status: :failed,
            last_error: safe_error_message
          )
        end

        if enrollment.completed? && !enrollment.cancelled?
          enrollment.update!(
            status: :active,
            last_error: nil
          )
        end

        AuditService.record!(
          account: enrollment.account,
          enrollment: enrollment,
          actor: nil,
          event_type: 'aftercare_step_dispatch_failed',
          payload: {
            step_id: step.id,
            dispatch_log_id: @dispatch_log.id,
            message_id: @message.id,
            error: safe_error_message
          }
        )
      end
    end

    def sync_success!
      step = @dispatch_log.aftercare_enrollment_step
      enrollment = @dispatch_log.aftercare_enrollment

      ActiveRecord::Base.transaction do
        @dispatch_log.update!(
          status: 'sent',
          provider_message_id: @message.source_id,
          sent_at: Time.current,
          error_message: nil
        )

        unless step.status_cancelled?
          step.update!(
            status: :sent,
            last_error: nil
          )
        end

        complete_enrollment_if_finished!(enrollment)
      end
    end

    def complete_enrollment_if_finished!(enrollment)
      return if enrollment.cancelled?

      remaining_steps = enrollment.aftercare_enrollment_steps
                                  .where(enabled: true)
                                  .where.not(status: [
                                               AftercareEnrollmentStep.statuses[:sent],
                                               AftercareEnrollmentStep.statuses[:cancelled],
                                               AftercareEnrollmentStep.statuses[:skipped]
                                             ])

      return if remaining_steps.exists?

      enrollment.update!(
        status: :completed,
        last_error: nil
      )
    end
  end
end
