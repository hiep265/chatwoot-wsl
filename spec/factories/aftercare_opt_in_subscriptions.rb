FactoryBot.define do
  factory :aftercare_opt_in_subscription do
    association :aftercare_enrollment
    topic { aftercare_enrollment.aftercare_sequence.opt_in_topic }
    status { :not_requested }
    provider { 'meta' }
    capability_status { 'supported' }
  end
end
