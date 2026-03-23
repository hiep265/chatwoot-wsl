module Aftercare
  class ResumeEnrollmentService
    class ResumeNotAllowedError < StandardError; end

    def initialize(enrollment:, actor: nil)
      @enrollment = enrollment
      @actor = actor
    end

    def perform
      validate_resumable!

      ActiveRecord::Base.transaction do
        @enrollment.update!(
          status: :active,
          paused_at: nil,
          last_error: nil
        )

        AuditService.record!(
          account: @enrollment.account,
          enrollment: @enrollment,
          actor: @actor,
          event_type: 'aftercare_enrollment_resumed',
          payload: {
            enrollment_id: @enrollment.id
          }
        )
      end

      @enrollment
    end

    private

    def validate_resumable!
      raise ResumeNotAllowedError, 'Only paused enrollments can be resumed' unless @enrollment.paused?
      raise ResumeNotAllowedError, 'Enrollment requires a subscribed opt-in to resume' unless @enrollment.aftercare_opt_in_subscription&.subscribed?
    end
  end
end
