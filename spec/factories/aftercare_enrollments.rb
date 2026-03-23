FactoryBot.define do
  factory :aftercare_enrollment do
    account
    conversation { create(:conversation, account: account) }
    contact { conversation.contact }
    inbox { conversation.inbox }
    association :aftercare_sequence
    created_by { association :user, account: account }
    status { :draft }
    channel_type { inbox.channel_type }
    channel_key { 'messenger' }
    staff_note { 'Khách đã mua sản phẩm mới' }
    timezone_name { 'Asia/Bangkok' }
    anchor_at { Time.current }
    idempotency_key { "#{account.id}:#{conversation.id}:#{aftercare_sequence.id}:#{anchor_at.to_i}" }
  end
end
