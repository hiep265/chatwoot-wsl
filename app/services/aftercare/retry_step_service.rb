module Aftercare
  class RetryStepService
    class RetryNotAllowedError < StandardError; end

    def initialize(step:, actor: nil)
      @step = step
      @enrollment = step.aftercare_enrollment
      @actor = actor
    end

    def perform
      validate_retryable!

      ActiveRecord::Base.transaction do
        @step.update!(
          status: :scheduled,
          last_error: nil
        )

        AuditService.record!(
          account: @enrollment.account,
          enrollment: @enrollment,
          actor: @actor,
          event_type: 'aftercare_step_retry_requested',
          payload: {
            step_id: @step.id,
            enrollment_id: @enrollment.id
          }
        )
      end

      Aftercare::DispatchStepJob.perform_later(@step.id)
      @step
    end

    private

    def validate_retryable!
      raise RetryNotAllowedError, 'Cancelled enrollments cannot retry steps' if @enrollment.cancelled?
      raise RetryNotAllowedError, 'Only failed aftercare steps can be retried' unless @step.status_failed?
    end
  end
end
