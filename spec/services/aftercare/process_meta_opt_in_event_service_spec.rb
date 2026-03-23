require 'rails_helper'

RSpec.describe Aftercare::ProcessMetaOptInEventService do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:facebook_channel) { create(:channel_facebook_page, account: account) }
  let(:inbox) { create(:inbox, account: account, channel: facebook_channel) }
  let(:contact) { create(:contact, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: 'meta-contact-123') }
  let(:conversation) do
    create(
      :conversation,
      account: account,
      inbox: inbox,
      contact: contact,
      contact_inbox: contact_inbox
    )
  end
  let(:enrollment) do
    create(
      :aftercare_enrollment,
      account: account,
      conversation: conversation,
      contact: contact,
      inbox: inbox,
      created_by: administrator,
      status: :pending_optin
    )
  end
  let(:subscription) do
    create(
      :aftercare_opt_in_subscription,
      aftercare_enrollment: enrollment,
      status: :requested,
      provider: 'meta',
      capability_status: 'supported'
    )
  end
  let(:correlation_payload) do
    {
      account_id: account.id,
      conversation_id: conversation.id,
      aftercare_enrollment_id: enrollment.id,
      aftercare_subscription_id: subscription.id,
      topic: subscription.topic
    }
  end

  before do
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
    allow(Facebook::Messenger::Subscriptions).to receive(:unsubscribe).and_return(true)
  end

  it 'activates the subscription from a Meta notification_messages opt-in payload' do
    payload = {
      sender: { id: contact_inbox.source_id },
      recipient: { id: facebook_channel.page_id },
      timestamp: Time.current.to_i,
      optin: {
        type: 'notification_messages',
        payload: correlation_payload.to_json,
        notification_messages_token: 'meta-notification-token-123',
        notification_messages_timezone: enrollment.timezone_name,
        token_expiry_timestamp: 30.days.from_now.to_i,
        user_token_status: 'NOT_REFRESHED',
        title: enrollment.aftercare_sequence.name
      }
    }

    described_class.new(payload: payload).perform

    expect(subscription.reload.status).to eq('subscribed')
    expect(subscription.token_ref).to eq('meta-notification-token-123')
    expect(subscription.expires_at).to be_present
    expect(subscription.webhook_payload).to include(
      'raw_payload' => hash_including(
        'recipient' => { 'id' => facebook_channel.page_id }
      )
    )
    expect(enrollment.reload.status).to eq('active')
    expect(
      enrollment.aftercare_audit_events.where(event_type: 'aftercare_opt_in_subscribed').count
    ).to eq(1)
  end

  it 'accepts millisecond timestamps from the webhook payload' do
    now_ms = (Time.current.to_f * 1000).to_i
    expiry_ms = (30.days.from_now.to_f * 1000).to_i
    payload = {
      sender: { id: contact_inbox.source_id },
      recipient: { id: facebook_channel.page_id },
      timestamp: now_ms,
      optin: {
        type: 'notification_messages',
        payload: correlation_payload.to_json,
        notification_messages_token: 'meta-notification-token-456',
        token_expiry_timestamp: expiry_ms
      }
    }

    described_class.new(payload: payload).perform

    expect(subscription.reload.subscribed_at).to be_within(5.seconds).of(Time.current)
    expect(subscription.expires_at).to be_within(5.seconds).of(30.days.from_now)
    expect(enrollment.reload.activated_at).to be_within(5.seconds).of(Time.current)
  end

  it 'marks the subscription revoked when the user stops notification messages' do
    payload = {
      sender: { id: contact_inbox.source_id },
      recipient: { id: facebook_channel.page_id },
      timestamp: Time.current.to_i,
      optin: {
        type: 'notification_messages',
        payload: correlation_payload.to_json,
        notification_messages_token: 'meta-notification-token-123',
        notification_messages_status: 'STOP NOTIFICATIONS',
        token_expiry_timestamp: 30.days.from_now.to_i
      }
    }

    described_class.new(payload: payload).perform

    expect(subscription.reload.status).to eq('revoked')
    expect(enrollment.reload.status).to eq('expired')
    expect(subscription.last_error).to eq('opt-in revoked')
  end
end
