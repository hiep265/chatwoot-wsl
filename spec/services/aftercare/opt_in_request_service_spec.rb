require 'rails_helper'

RSpec.describe Aftercare::OptInRequestService do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:facebook_channel) { create(:channel_facebook_page, account: account) }
  let(:inbox) { create(:inbox, account: account, channel: facebook_channel) }
  let(:contact) { create(:contact, :with_email, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
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
      status: :not_requested,
      provider: 'gmail',
      capability_status: 'supported'
    )
  end

  before do
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
    allow(Facebook::Messenger::Subscriptions).to receive(:unsubscribe).and_return(true)
    allow(Aftercare::GmailDeliveryCapability).to receive(:smtp_ready?).and_return(true)
  end

  it 'marks the subscription and enrollment active when Gmail delivery is ready' do
    described_class.new(subscription: subscription, actor: administrator).perform

    expect(subscription.reload.status).to eq('subscribed')
    expect(subscription.provider).to eq('gmail')
    expect(subscription.requested_at).to be_present
    expect(subscription.subscribed_at).to be_present
    expect(subscription.last_error).to be_nil
    expect(enrollment.reload.status).to eq('active')
    expect(enrollment.activated_at).to be_present
    expect(
      enrollment.aftercare_audit_events.where(event_type: 'aftercare_opt_in_subscribed').last.payload
    ).to include(
      'subscription_id' => subscription.id,
      'source' => 'gmail_delivery_ready'
    )
  end

  it 'blocks the enrollment when the contact does not have an email address for Gmail delivery' do
    contact.update!(email: nil)

    expect do
      described_class.new(subscription: subscription, actor: administrator).perform
    end.to raise_error(Aftercare::OptInRequestService::GmailDeliveryUnavailableError, /email/i)

    expect(subscription.reload.status).to eq('unsupported_channel_capability')
    expect(subscription.capability_status).to eq('email_missing')
    expect(subscription.last_error).to match(/email/i)
    expect(enrollment.reload.status).to eq('blocked_capability_disabled')
    expect(enrollment.last_error).to match(/email/i)
    expect(
      enrollment.aftercare_audit_events.where(event_type: 'aftercare_opt_in_request_failed').last.payload
    ).to include(
      'capability_status' => 'email_missing'
    )
  end

  it 'blocks the enrollment when Gmail SMTP is not configured' do
    allow(Aftercare::GmailDeliveryCapability).to receive(:smtp_ready?).and_return(false)

    expect do
      described_class.new(subscription: subscription, actor: administrator).perform
    end.to raise_error(Aftercare::OptInRequestService::GmailDeliveryUnavailableError, /smtp/i)

    expect(subscription.reload.status).to eq('unsupported_channel_capability')
    expect(subscription.capability_status).to eq('smtp_not_configured')
    expect(subscription.last_error).to match(/smtp/i)
    expect(enrollment.reload.status).to eq('blocked_capability_disabled')
    expect(enrollment.last_error).to match(/smtp/i)
  end

  it 'activates Gmail delivery for instagram conversations as well' do
    instagram_channel = create(:channel_instagram, account: account)
    instagram_inbox = instagram_channel.inbox
    instagram_contact = create(:contact, :with_email, account: account)
    instagram_contact_inbox = create(:contact_inbox, contact: instagram_contact, inbox: instagram_inbox)
    instagram_conversation = create(
      :conversation,
      account: account,
      inbox: instagram_inbox,
      contact: instagram_contact,
      contact_inbox: instagram_contact_inbox
    )
    instagram_enrollment = create(
      :aftercare_enrollment,
      account: account,
      conversation: instagram_conversation,
      contact: instagram_contact,
      inbox: instagram_inbox,
      created_by: administrator,
      status: :pending_optin,
      channel_key: 'instagram'
    )
    instagram_subscription = create(
      :aftercare_opt_in_subscription,
      aftercare_enrollment: instagram_enrollment,
      status: :not_requested,
      provider: 'gmail',
      capability_status: 'supported'
    )

    described_class.new(subscription: instagram_subscription, actor: administrator).perform

    expect(instagram_subscription.reload.status).to eq('subscribed')
    expect(instagram_subscription.provider).to eq('gmail')
    expect(instagram_enrollment.reload.status).to eq('active')
  end
end
