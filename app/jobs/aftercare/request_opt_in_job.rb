module Aftercare
  class RequestOptInJob < ApplicationJob
    queue_as :scheduled_jobs

    def perform(enrollment_id)
      enrollment = AftercareEnrollment.find(enrollment_id)
      subscription = enrollment.aftercare_opt_in_subscription
      return if subscription.blank?

      Aftercare::OptInRequestService.new(subscription: subscription, actor: enrollment.created_by).perform
    end
  end
end
