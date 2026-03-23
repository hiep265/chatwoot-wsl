require 'rails_helper'

RSpec.describe Aftercare::DispatchStepService do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  before do
    stub_request(:post, /graph.facebook.com/)
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
    allow(Facebook::Messenger::Subscriptions).to receive(:unsubscribe).and_return(true)
    allow(Aftercare::GmailDeliveryCapability).to receive(:smtp_ready?).and_return(true)
    GlobalConfig.clear_cache
    clear_enqueued_jobs
  end

  it 'keeps the step sending until provider delivery is confirmed, then marks it sent' do
    facebook_channel = create(:channel_facebook_page, account: account)
    inbox = create(:inbox, account: account, channel: facebook_channel)
    conversation = create(:conversation, account: account, inbox: inbox)
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      content: 'Khách vừa phản hồi gần đây',
      created_at: 2.hours.ago
    )
    enrollment = create(
      :aftercare_enrollment,
      account: account,
      conversation: conversation,
      contact: conversation.contact,
      inbox: inbox,
      created_by: administrator,
      status: :active
    )
    step = create(
      :aftercare_enrollment_step,
      aftercare_enrollment: enrollment,
      status: :scheduled,
      draft_status: :ready,
      draft_body: 'Chào bạn, mình hỏi thăm trải nghiệm sau mua nhé.',
      draft_generated_at: 20.minutes.ago,
      scheduled_for: 5.minutes.ago
    )
    enrollment.create_aftercare_opt_in_subscription!(
      topic: enrollment.aftercare_sequence.opt_in_topic,
      provider: 'meta',
      capability_status: 'supported',
      status: :subscribed,
      token_ref: 'meta-token'
    )

    expect do
      described_class.new(step: step).perform
    end.to change { conversation.messages.outgoing.count }.by(1)
      .and change(AftercareDispatchLog, :count).by(1)

    step.reload
    dispatch_log = step.aftercare_dispatch_logs.last

    expect(step.status).to eq('sending')
    expect(dispatch_log.status).to eq('sending')
    expect(dispatch_log.provider).to eq('meta')
    expect(dispatch_log.message).to be_present
    expect(dispatch_log.message.content_attributes).to include(
      'aftercare_delivery_lane' => 'standard',
      'aftercare_opt_in_subscription_id' => enrollment.aftercare_opt_in_subscription.id
    )
    expect(dispatch_log.metadata).to include(
      'delivery_lane' => 'standard',
      'dispatch_reason' => 'within_standard_window'
    )
    expect(enrollment.reload.status).to eq('active')
    expect(
      enrollment.aftercare_audit_events.where(event_type: 'aftercare_step_dispatched').count
    ).to eq(1)

    dispatch_log.message.update!(source_id: 'meta-message-123')

    expect(step.reload.status).to eq('sent')
    expect(dispatch_log.reload.status).to eq('sent')
    expect(dispatch_log.provider_message_id).to eq('meta-message-123')
    expect(dispatch_log.sent_at).to be_present
    expect(enrollment.reload.status).to eq('completed')
  end

  it 'uses the gmail lane outside 24 hours when the contact email is available' do
    facebook_channel = create(:channel_facebook_page, account: account)
    inbox = create(:inbox, account: account, channel: facebook_channel)
    conversation = create(:conversation, account: account, inbox: inbox)
    conversation.contact.update!(email: 'lan@example.com')
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      content: 'Khách đã tương tác từ vài ngày trước',
      created_at: 3.days.ago
    )
    enrollment = create(
      :aftercare_enrollment,
      account: account,
      conversation: conversation,
      contact: conversation.contact,
      inbox: inbox,
      created_by: administrator,
      status: :active
    )
    step = create(
      :aftercare_enrollment_step,
      aftercare_enrollment: enrollment,
      status: :scheduled,
      draft_status: :ready,
      draft_body: 'Mình gửi follow-up sau mua theo opt-in nhé.',
      draft_generated_at: 20.minutes.ago,
      scheduled_for: 5.minutes.ago
    )
    subscription = enrollment.create_aftercare_opt_in_subscription!(
      topic: enrollment.aftercare_sequence.opt_in_topic,
      provider: 'gmail',
      capability_status: 'supported',
      status: :subscribed,
      token_ref: nil
    )
    gmail_delivery = instance_double(Aftercare::GmailDeliveryService, perform: true)
    allow(Aftercare::GmailDeliveryService).to receive(:new).and_return(gmail_delivery)

    described_class.new(step: step).perform

    dispatch_log = step.reload.aftercare_dispatch_logs.last

    expect(Aftercare::GmailDeliveryService).to have_received(:new).with(
      message: dispatch_log.message
    )
    expect(gmail_delivery).to have_received(:perform)
    expect(dispatch_log.message.content_attributes).to include(
      'aftercare_delivery_lane' => 'gmail',
      'aftercare_opt_in_subscription_id' => subscription.id
    )
    expect(dispatch_log.metadata).to include(
      'delivery_lane' => 'gmail',
      'dispatch_reason' => 'outside_standard_window_with_gmail_ready',
      'delivery_email' => 'lan@example.com'
    )
    expect(dispatch_log.provider).to eq('gmail')
  end

  it 'marks the step failed when the message cannot be created' do
    facebook_channel = create(:channel_facebook_page, account: account)
    inbox = create(:inbox, account: account, channel: facebook_channel)
    conversation = create(:conversation, account: account, inbox: inbox)
    enrollment = create(
      :aftercare_enrollment,
      account: account,
      conversation: conversation,
      contact: conversation.contact,
      inbox: inbox,
      created_by: administrator,
      status: :active
    )
    step = create(
      :aftercare_enrollment_step,
      aftercare_enrollment: enrollment,
      status: :scheduled,
      draft_status: :ready,
      draft_body: '',
      scheduled_for: 5.minutes.ago
    )
    enrollment.create_aftercare_opt_in_subscription!(
      topic: enrollment.aftercare_sequence.opt_in_topic,
      provider: 'meta',
      capability_status: 'supported',
      status: :subscribed,
      token_ref: 'meta-token'
    )

    expect do
      described_class.new(step: step).perform
    end.to raise_error(Aftercare::DispatchStepService::DispatchError)

    expect(step.reload.status).to eq('failed')
    expect(step.last_error).to be_present
    expect(
      enrollment.aftercare_audit_events.where(event_type: 'aftercare_step_dispatch_failed').count
    ).to eq(1)
  end

  it 'blocks the step outside 24 hours when the contact email is missing' do
    facebook_channel = create(:channel_facebook_page, account: account)
    inbox = create(:inbox, account: account, channel: facebook_channel)
    conversation = create(:conversation, account: account, inbox: inbox)
    conversation.contact.update!(email: nil)
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      content: 'Khách đã im lặng hơn 24h',
      created_at: 3.days.ago
    )
    enrollment = create(
      :aftercare_enrollment,
      account: account,
      conversation: conversation,
      contact: conversation.contact,
      inbox: inbox,
      created_by: administrator,
      status: :active
    )
    step = create(
      :aftercare_enrollment_step,
      aftercare_enrollment: enrollment,
      status: :scheduled,
      draft_status: :ready,
      draft_body: 'Follow-up sau mua',
      draft_generated_at: 20.minutes.ago,
      scheduled_for: 5.minutes.ago
    )
    enrollment.create_aftercare_opt_in_subscription!(
      topic: enrollment.aftercare_sequence.opt_in_topic,
      provider: 'gmail',
      capability_status: 'supported',
      status: :subscribed,
      token_ref: nil
    )

    expect do
      described_class.new(step: step).perform
    end.to raise_error(
      Aftercare::DispatchStepService::DispatchError,
      /email/i
    )

    expect(step.reload.status).to eq('failed')
    expect(enrollment.reload.status).to eq('blocked_capability_disabled')
    expect(enrollment.aftercare_opt_in_subscription.reload.status).to eq('unsupported_channel_capability')
  end

  it 'marks the step failed when the provider later reports a delivery error' do
    facebook_channel = create(:channel_facebook_page, account: account)
    inbox = create(:inbox, account: account, channel: facebook_channel)
    conversation = create(:conversation, account: account, inbox: inbox)
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      content: 'Khách vừa tương tác gần đây',
      created_at: 2.hours.ago
    )
    enrollment = create(
      :aftercare_enrollment,
      account: account,
      conversation: conversation,
      contact: conversation.contact,
      inbox: inbox,
      created_by: administrator,
      status: :active
    )
    step = create(
      :aftercare_enrollment_step,
      aftercare_enrollment: enrollment,
      status: :scheduled,
      draft_status: :ready,
      draft_body: 'Chào bạn, mình hỏi thăm trải nghiệm sau mua nhé.',
      draft_generated_at: 20.minutes.ago,
      scheduled_for: 5.minutes.ago
    )
    enrollment.create_aftercare_opt_in_subscription!(
      topic: enrollment.aftercare_sequence.opt_in_topic,
      provider: 'gmail',
      capability_status: 'supported',
      status: :subscribed,
      token_ref: nil
    )

    described_class.new(step: step).perform

    dispatch_log = step.reload.aftercare_dispatch_logs.last

    expect(step.status).to eq('sending')
    expect(dispatch_log.status).to eq('sending')

    Messages::StatusUpdateService.new(
      dispatch_log.message,
      'failed',
      'Invalid OAuth access token'
    ).perform

    expect(step.reload.status).to eq('failed')
    expect(step.last_error).to eq('Invalid OAuth access token')
    expect(dispatch_log.reload.status).to eq('failed')
    expect(dispatch_log.error_message).to eq('Invalid OAuth access token')
    expect(enrollment.reload.status).to eq('active')
  end

  it 'refreshes the draft before sending when newer conversation messages arrived' do
    facebook_channel = create(:channel_facebook_page, account: account)
    inbox = create(:inbox, account: account, channel: facebook_channel)
    conversation = create(:conversation, account: account, inbox: inbox)
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      content: 'Khách tương tác gần đây',
      created_at: 2.hours.ago
    )
    enrollment = create(
      :aftercare_enrollment,
      account: account,
      conversation: conversation,
      contact: conversation.contact,
      inbox: inbox,
      created_by: administrator,
      status: :active
    )
    step = create(
      :aftercare_enrollment_step,
      aftercare_enrollment: enrollment,
      status: :scheduled,
      draft_status: :ready,
      draft_body: 'Draft cũ',
      draft_generated_at: 2.hours.ago,
      scheduled_for: 5.minutes.ago
    )
    enrollment.create_aftercare_opt_in_subscription!(
      topic: enrollment.aftercare_sequence.opt_in_topic,
      provider: 'meta',
      capability_status: 'supported',
      status: :subscribed,
      token_ref: 'meta-token'
    )
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      content: 'Khách vừa cập nhật tiến độ mới',
      created_at: 10.minutes.ago
    )

    refresh_service = instance_double(Aftercare::GenerateStepDraftService)
    allow(Aftercare::GenerateStepDraftService)
      .to receive(:new)
      .with(step: step, actor: administrator)
      .and_return(refresh_service)
    allow(refresh_service).to receive(:perform) do
      step.update!(
        draft_status: :ready,
        draft_body: 'Draft đã làm mới theo tin nhắn mới',
        draft_generated_at: Time.current
      )
    end

    described_class.new(step: step).perform

    expect(refresh_service).to have_received(:perform)
    expect(conversation.messages.outgoing.last.content).to eq(
      'Draft đã làm mới theo tin nhắn mới'
    )
  end
end
