FactoryBot.define do
  factory :aftercare_sequence do
    code { "aftercare_#{SecureRandom.hex(4)}" }
    name { 'Aftercare sequence' }
    description { 'Sequence for post-purchase follow-up' }
    channel_scope { 'messenger_instagram' }
    opt_in_topic { "aftercare.#{code}" }
    default_timezone { 'Asia/Bangkok' }
    active { true }
  end
end
