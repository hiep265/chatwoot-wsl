module Aftercare
  class CancelEnrollmentService
    def initialize(enrollment:, actor: nil)
      @enrollment = enrollment
      @actor = actor
    end

    def perform
      ActiveRecord::Base.transaction do
        @enrollment.update!(
          status: :cancelled,
          cancelled_at: Time.current,
          last_error: nil
        )

        @enrollment.aftercare_enrollment_steps
                   .where.not(status: AftercareEnrollmentStep.statuses[:sent])
                   .update_all(
                     status: AftercareEnrollmentStep.statuses[:cancelled],
                     updated_at: Time.current
                   )

        AuditService.record!(
          account: @enrollment.account,
          enrollment: @enrollment,
          actor: @actor,
          event_type: 'aftercare_enrollment_cancelled',
          payload: {
            enrollment_id: @enrollment.id
          }
        )
      end

      @enrollment
    end
  end
end
