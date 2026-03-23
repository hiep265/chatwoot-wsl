require 'rails_helper'

RSpec.describe Aftercare::GenerateStepDraftService do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  before do
    stub_request(:post, /graph.facebook.com/)
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
    allow(Facebook::Messenger::Subscriptions).to receive(:unsubscribe).and_return(true)
    GlobalConfig.clear_cache
  end

  describe '#perform' do
    it 'sends the latest 30 conversation messages to chatbotlevan and stores the returned draft' do
      facebook_channel = create(:channel_facebook_page, account: account)
      inbox = create(:inbox, account: account, channel: facebook_channel)
      conversation = create(:conversation, account: account, inbox: inbox)
      sequence = create(
        :aftercare_sequence,
        code: 'post_purchase_checkin_service_spec',
        name: 'Chăm sóc sau mua',
        opt_in_topic: 'aftercare.post_purchase_checkin_service_spec'
      )
      enrollment = create(
        :aftercare_enrollment,
        account: account,
        conversation: conversation,
        contact: conversation.contact,
        inbox: inbox,
        aftercare_sequence: sequence,
        created_by: administrator,
        status: :active,
        staff_note: 'Khách mới mua gói cơ bản, follow-up nhẹ nhàng'
      )
      step = create(
        :aftercare_enrollment_step,
        aftercare_enrollment: enrollment,
        title: 'Hỏi thăm ngày 1',
        instructions: 'Hỏi khách đã bắt đầu dùng sản phẩm chưa'
      )

      35.times do |index|
        create(
          :message,
          account: account,
          inbox: inbox,
          conversation: conversation,
          message_type: index.even? ? :incoming : :outgoing,
          content: "message-#{index + 1}",
          created_at: (35 - index).minutes.ago
        )
      end

      captured_body = nil

      with_modified_env(
        'CHATBOTLEVAN_INTERNAL_BASE_URL' => '',
        'CHATBOTLEVAN_BASE_URL' => 'http://chatbotlevan.local',
        'CHATBOTLEVAN_API_TOKEN' => 'aftercare-secret'
      ) do
        stub_request(:post, 'http://chatbotlevan.local/internal/aftercare/drafts')
          .to_return do |request|
            captured_body = JSON.parse(request.body)
            {
              status: 200,
              body: {
                draft_text: 'Chào bạn, bên mình hỏi thăm xem bạn đã bắt đầu triển khai chưa nhé.',
                summary: 'Gentle progress check',
                version_fingerprint: 'draft-v2'
              }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            }
          end

        described_class.new(step: step, actor: administrator).perform
      end

      expect(captured_body['recent_messages'].length).to eq(30)
      expect(captured_body['recent_messages'].first['content']).to eq('message-6')
      expect(captured_body['recent_messages'].last['content']).to eq('message-35')

      step.reload
      expect(step.draft_status).to eq('ready')
      expect(step.draft_body).to eq('Chào bạn, bên mình hỏi thăm xem bạn đã bắt đầu triển khai chưa nhé.')
      expect(step.draft_summary).to eq('Gentle progress check')
      expect(step.draft_version).to eq('draft-v2')
      expect(step.draft_generated_at).to be_present
      expect(step.draft_input_snapshot).to be_present
      expect(step.draft_error).to be_blank
    end

    it 'marks the step as failed_generation when chatbotlevan returns an error' do
      facebook_channel = create(:channel_facebook_page, account: account)
      inbox = create(:inbox, account: account, channel: facebook_channel)
      conversation = create(:conversation, account: account, inbox: inbox)
      enrollment = create(
        :aftercare_enrollment,
        account: account,
        conversation: conversation,
        contact: conversation.contact,
        inbox: inbox,
        created_by: administrator
      )
      step = create(:aftercare_enrollment_step, aftercare_enrollment: enrollment)

      with_modified_env(
        'CHATBOTLEVAN_INTERNAL_BASE_URL' => '',
        'CHATBOTLEVAN_BASE_URL' => 'http://chatbotlevan.local',
        'CHATBOTLEVAN_API_TOKEN' => 'aftercare-secret'
      ) do
        stub_request(:post, 'http://chatbotlevan.local/internal/aftercare/drafts')
          .to_return(
            status: 500,
            body: { error: 'draft_failed' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        expect do
          described_class.new(step: step, actor: administrator).perform
        end.to raise_error(Aftercare::GenerateStepDraftService::DraftGenerationError)
      end

      step.reload
      expect(step.draft_status).to eq('failed_generation')
      expect(step.draft_error).to include('draft_failed')
    end

    it 'prefers CHATBOTLEVAN_INTERNAL_BASE_URL for server-to-server draft requests' do
      facebook_channel = create(:channel_facebook_page, account: account)
      inbox = create(:inbox, account: account, channel: facebook_channel)
      conversation = create(:conversation, account: account, inbox: inbox)
      enrollment = create(
        :aftercare_enrollment,
        account: account,
        conversation: conversation,
        contact: conversation.contact,
        inbox: inbox,
        created_by: administrator
      )
      step = create(:aftercare_enrollment_step, aftercare_enrollment: enrollment)

      with_modified_env(
        'CHATBOTLEVAN_INTERNAL_BASE_URL' => 'http://host.docker.internal:8012',
        'CHATBOTLEVAN_BASE_URL' => 'https://chatbotlevan2.hiep265.shop',
        'CHATBOTLEVAN_API_TOKEN' => 'aftercare-secret'
      ) do
        stub_request(:post, 'http://host.docker.internal:8012/internal/aftercare/drafts')
          .to_return(
            status: 200,
            body: {
              draft_text: 'Noi dung draft tu internal url',
              summary: 'internal route',
              version_fingerprint: 'draft-internal'
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )
        stub_request(:post, 'https://chatbotlevan2.hiep265.shop/internal/aftercare/drafts')
          .to_return(
            status: 500,
            body: { error: 'should_not_hit_public_base' }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        described_class.new(step: step, actor: administrator).perform
      end

      step.reload
      expect(step.draft_status).to eq('ready')
      expect(step.draft_body).to eq('Noi dung draft tu internal url')
      expect(a_request(:post, 'http://host.docker.internal:8012/internal/aftercare/drafts')).to have_been_made.once
      expect(a_request(:post, 'https://chatbotlevan2.hiep265.shop/internal/aftercare/drafts')).not_to have_been_made
    end
  end
end
