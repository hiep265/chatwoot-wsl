FactoryBot.define do
  factory :aftercare_enrollment_step do
    association :aftercare_enrollment
    aftercare_sequence_step { nil }
    sequence(:position) { |n| n }
    title { "Enrollment step #{position}" }
    instructions { 'Check on the customer.' }
    status { :scheduled }
    draft_status { :not_requested }
    offset_minutes { position * 1440 }
    scheduled_for { Time.current + offset_minutes.minutes }
    enabled { true }
  end
end
