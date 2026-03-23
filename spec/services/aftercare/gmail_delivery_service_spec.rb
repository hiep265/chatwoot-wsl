require 'rails_helper'

RSpec.describe Aftercare::GmailDeliveryService do
  let(:account) { create(:account) }
  let(:facebook_channel) { create(:channel_facebook_page, account: account) }
  let(:inbox) { create(:inbox, account: account, channel: facebook_channel) }
  let(:contact) { create(:contact, :with_email, account: account) }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }
  let(:message) do
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      content: 'Follow-up sau mua qua Gmail',
      content_attributes: {
        is_bot_generated: true,
        aftercare_delivery_lane: 'gmail'
      }
    )
  end

  let(:mailer_context) { instance_double(ConversationReplyMailer) }
  let(:delivery) { instance_double(ActionMailer::MessageDelivery) }
  let(:mail_message) { instance_double(Mail::Message, message_id: '<aftercare-gmail-123@example.com>') }

  before do
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
    allow(Facebook::Messenger::Subscriptions).to receive(:unsubscribe).and_return(true)
    allow(ConversationReplyMailer).to receive(:with).with(account: account).and_return(mailer_context)
    allow(mailer_context).to receive(:email_reply).with(message).and_return(delivery)
  end

  it 'sends the aftercare message through ConversationReplyMailer and stores the email message id' do
    allow(delivery).to receive(:deliver_now).and_return(mail_message)

    described_class.new(message: message).perform

    expect(ConversationReplyMailer).to have_received(:with).with(account: account)
    expect(mailer_context).to have_received(:email_reply).with(message)
    expect(delivery).to have_received(:deliver_now)
    expect(message.reload.source_id).to eq('<aftercare-gmail-123@example.com>')
  end

  it 'marks the message failed when Gmail delivery raises an error' do
    allow(delivery).to receive(:deliver_now).and_raise(StandardError.new('SMTP connection failed'))

    described_class.new(message: message).perform

    expect(message.reload.status).to eq('failed')
    expect(message.reload.external_error).to eq('SMTP connection failed')
  end
end
