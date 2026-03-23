FactoryBot.define do
  factory :aftercare_sequence_step do
    association :aftercare_sequence
    sequence(:position) { |n| n }
    title { "Step #{position}" }
    instructions { 'Send a friendly aftercare follow-up.' }
    offset_minutes { position * 1440 }
    enabled { true }
  end
end
