module Aftercare
  class UpdateStepDraftService
    class InvalidDraftError < StandardError; end

    def initialize(step:, draft_body:, actor: nil)
      @step = step
      @enrollment = step.aftercare_enrollment
      @draft_body = draft_body
      @actor = actor
    end

    def perform
      normalized_draft_body = @draft_body.to_s.strip
      raise InvalidDraftError, 'Draft body cannot be blank' if normalized_draft_body.blank?

      @step.update!(
        draft_status: :ready,
        draft_body: normalized_draft_body,
        draft_summary: nil,
        draft_version: manual_draft_version,
        draft_generated_at: Time.current,
        draft_error: nil,
        last_error: nil
      )

      AuditService.record!(
        account: @enrollment.account,
        enrollment: @enrollment,
        actor: @actor,
        event_type: 'aftercare_draft_manually_updated',
        payload: {
          step_id: @step.id,
          draft_status: @step.draft_status,
          draft_version: @step.draft_version
        }
      )

      @step
    end

    private

    def manual_draft_version
      "manual-#{Time.current.utc.iso8601(6)}"
    end
  end
end
