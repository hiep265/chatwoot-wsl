module Aftercare
  class ProcessDueStepsJob < ApplicationJob
    queue_as :scheduled_jobs

    def perform
      due_steps.find_each(batch_size: 100) do |step|
        Aftercare::DispatchStepJob.perform_later(step.id)
      end
    end

    private

    def due_steps
      AftercareEnrollmentStep
        .joins(:aftercare_enrollment)
        .where(aftercare_enrollments: { status: AftercareEnrollment.statuses[:active] })
        .where(status: AftercareEnrollmentStep.statuses[:scheduled], enabled: true)
        .where('scheduled_for <= ?', Time.current)
    end
  end
end
