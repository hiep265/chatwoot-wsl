require 'rails_helper'

RSpec.describe Aftercare::DeliveryLaneResolver do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  before do
    stub_request(:post, /graph.facebook.com/)
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
    allow(Facebook::Messenger::Subscriptions).to receive(:unsubscribe).and_return(true)
    allow(Aftercare::GmailDeliveryCapability).to receive(:smtp_ready?).and_return(true)
  end

  it 'keeps a recent conversation on the standard delivery lane' do
    facebook_channel = create(:channel_facebook_page, account: account)
    inbox = create(:inbox, account: account, channel: facebook_channel)
    conversation = create(:conversation, account: account, inbox: inbox)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: 2.hours.ago)
    enrollment = create(
      :aftercare_enrollment,
      account: account,
      conversation: conversation,
      contact: conversation.contact,
      inbox: inbox,
      created_by: administrator,
      status: :active
    )
    enrollment.create_aftercare_opt_in_subscription!(
      topic: enrollment.aftercare_sequence.opt_in_topic,
      provider: 'meta',
      capability_status: 'supported',
      status: :subscribed,
      token_ref: 'meta-token'
    )

    result = described_class.new(enrollment: enrollment).perform

    expect(result.lane).to eq('standard')
    expect(result.reason_code).to eq('within_standard_window')
    expect(result.window_expires_at).to be_present
  end

  it 'switches to the gmail lane when the conversation is outside 24h and the contact has an email address' do
    facebook_channel = create(:channel_facebook_page, account: account)
    inbox = create(:inbox, account: account, channel: facebook_channel)
    conversation = create(:conversation, account: account, inbox: inbox)
    conversation.contact.update!(email: 'lan@example.com')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: 3.days.ago)
    enrollment = create(
      :aftercare_enrollment,
      account: account,
      conversation: conversation,
      contact: conversation.contact,
      inbox: inbox,
      created_by: administrator,
      status: :active
    )
    enrollment.create_aftercare_opt_in_subscription!(
      topic: enrollment.aftercare_sequence.opt_in_topic,
      provider: 'gmail',
      capability_status: 'supported',
      status: :subscribed,
      token_ref: nil
    )

    result = described_class.new(enrollment: enrollment).perform

    expect(result.lane).to eq('gmail')
    expect(result.reason_code).to eq('outside_standard_window_with_gmail_ready')
    expect(result.delivery_email).to eq('lan@example.com')
  end

  it 'supports the gmail lane for instagram conversations that are outside 24h' do
    instagram_channel = create(:channel_instagram, account: account)
    inbox = instagram_channel.inbox
    conversation = create(:conversation, account: account, inbox: inbox)
    conversation.contact.update!(email: 'ig-customer@example.com')
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: 3.days.ago)
    enrollment = create(
      :aftercare_enrollment,
      account: account,
      conversation: conversation,
      contact: conversation.contact,
      inbox: inbox,
      created_by: administrator,
      status: :active,
      channel_key: 'instagram'
    )
    enrollment.create_aftercare_opt_in_subscription!(
      topic: enrollment.aftercare_sequence.opt_in_topic,
      provider: 'gmail',
      capability_status: 'supported',
      status: :subscribed,
      token_ref: nil
    )

    result = described_class.new(enrollment: enrollment).perform

    expect(result.lane).to eq('gmail')
    expect(result.reason_code).to eq('outside_standard_window_with_gmail_ready')
    expect(result.delivery_email).to eq('ig-customer@example.com')
  end

  it 'blocks dispatch when the conversation is outside 24h and the contact has no email address' do
    facebook_channel = create(:channel_facebook_page, account: account)
    inbox = create(:inbox, account: account, channel: facebook_channel)
    conversation = create(:conversation, account: account, inbox: inbox)
    conversation.contact.update!(email: nil)
    create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, created_at: 3.days.ago)
    enrollment = create(
      :aftercare_enrollment,
      account: account,
      conversation: conversation,
      contact: conversation.contact,
      inbox: inbox,
      created_by: administrator,
      status: :active
    )
    enrollment.create_aftercare_opt_in_subscription!(
      topic: enrollment.aftercare_sequence.opt_in_topic,
      provider: 'gmail',
      capability_status: 'supported',
      status: :subscribed,
      token_ref: nil
    )

    expect do
      described_class.new(enrollment: enrollment).perform
    end.to raise_error(
      Aftercare::DeliveryLaneResolver::DeliveryBlockedError,
      /email/i
    )
  end
end
