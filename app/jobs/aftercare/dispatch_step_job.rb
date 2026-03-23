module Aftercare
  class DispatchStepJob < ApplicationJob
    queue_as :scheduled_jobs

    def perform(step_id)
      step = AftercareEnrollmentStep.find(step_id)
      Aftercare::DispatchStepService.new(step: step).perform
    end
  end
end
