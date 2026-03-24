# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AftercareMailer do
  describe '#step_email' do
    let(:account) { create(:account, support_email: 'support@example.com') }
    let(:facebook_channel) { create(:channel_facebook_page, account: account) }
    let(:inbox) { create(:inbox, account: account, channel: facebook_channel) }
    let(:contact) { create(:contact, :with_email, account: account, name: 'Hà Mạnh Đà') }
    let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox) }
    let(:conversation) do
      create(
        :conversation,
        account: account,
        inbox: inbox,
        contact: contact,
        contact_inbox: contact_inbox,
        additional_attributes: {}
      )
    end
    let(:sequence) { create(:aftercare_sequence, account: account, name: 'Chăm sóc sau mua') }
    let(:enrollment) do
      create(
        :aftercare_enrollment,
        account: account,
        inbox: inbox,
        contact: contact,
        conversation: conversation,
        aftercare_sequence: sequence
      )
    end
    let(:step) do
      create(
        :aftercare_enrollment_step,
        aftercare_enrollment: enrollment,
        title: 'Ngay sau cọc đăng ký'
      )
    end
    let(:message_body) do
      <<~BODY.strip
        🎉 Hà Mạnh Đà đã đăng ký thành công!

        📋 CHECKLIST CHUẨN BỊ:
        1. Visa/Vé máy bay
        2. Đặt khách sạn gần địa điểm học
      BODY
    end
    let(:message) do
      create(
        :message,
        account: account,
        inbox: inbox,
        conversation: conversation,
        message_type: :outgoing,
        content: message_body,
        content_attributes: {
          is_bot_generated: true,
          aftercare_delivery_lane: 'gmail',
          aftercare_step_id: step.id
        }
      )
    end
    let(:mail) { described_class.with(account: account).step_email(message).deliver_now }

    before do
      allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
      allow(Facebook::Messenger::Subscriptions).to receive(:unsubscribe).and_return(true)
      allow_any_instance_of(described_class).to receive(:smtp_config_set_or_development?).and_return(true)
    end

    it 'renders a customer care sender instead of the inbox name' do
      expect(mail[:from].display_names).to eq(['Chăm sóc khách hàng'])
      expect(mail[:from].decoded).not_to include('Bridge WhatsApp')
    end

    it 'renders a formatted HTML email that preserves the draft line breaks' do
      html_part = mail.html_part || mail

      expect(mail.subject).to eq('Chăm sóc sau mua: Ngay sau cọc đăng ký')
      expect(html_part.body.decoded).to include('Tư vấn sau mua khóa học')
      expect(html_part.body.decoded).to include('Ngay sau cọc đăng ký')
      expect(html_part.body.decoded).to include('CHECKLIST CHUẨN BỊ')
      expect(html_part.body.decoded).to include('<br')
    end

    it 'renders the original draft content in the text part' do
      expect(mail.text_part.body.decoded).to include('🎉 Hà Mạnh Đà đã đăng ký thành công!')
      expect(mail.text_part.body.decoded).to include('1. Visa/Vé máy bay')
    end
  end
end
