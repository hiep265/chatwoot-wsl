module Aftercare
  class PauseEnrollmentService
    class PauseNotAllowedError < StandardError; end

    def initialize(enrollment:, actor: nil)
      @enrollment = enrollment
      @actor = actor
    end

    def perform
      raise PauseNotAllowedError, 'Only active enrollments can be paused' unless @enrollment.active?

      ActiveRecord::Base.transaction do
        @enrollment.update!(
          status: :paused,
          paused_at: Time.current,
          last_error: nil
        )

        AuditService.record!(
          account: @enrollment.account,
          enrollment: @enrollment,
          actor: @actor,
          event_type: 'aftercare_enrollment_paused',
          payload: {
            enrollment_id: @enrollment.id
          }
        )
      end

      @enrollment
    end
  end
end
