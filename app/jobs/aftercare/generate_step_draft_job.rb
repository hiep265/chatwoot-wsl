module Aftercare
  class GenerateStepDraftJob < ApplicationJob
    queue_as :scheduled_jobs

    def perform(step_id)
      step = AftercareEnrollmentStep.find(step_id)
      actor = step.aftercare_enrollment.created_by

      Aftercare::GenerateStepDraftService.new(step: step, actor: actor).perform
    end
  end
end
