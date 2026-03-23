require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Aftercare::EnrollmentStepsController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  before do
    stub_request(:post, /graph.facebook.com/)
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
    allow(Facebook::Messenger::Subscriptions).to receive(:unsubscribe).and_return(true)
    GlobalConfig.clear_cache
  end

  describe 'POST /api/v1/accounts/:account_id/aftercare/enrollments/:enrollment_id/steps/:id/regenerate_draft' do
    it 'regenerates the draft for the selected enrollment step and returns the updated payload' do
      facebook_channel = create(:channel_facebook_page, account: account)
      inbox = create(:inbox, account: account, channel: facebook_channel)
      conversation = create(:conversation, account: account, inbox: inbox)
      sequence = create(:aftercare_sequence)
      enrollment = create(
        :aftercare_enrollment,
        account: account,
        conversation: conversation,
        contact: conversation.contact,
        inbox: inbox,
        aftercare_sequence: sequence,
        created_by: administrator,
        status: :active
      )
      step = create(
        :aftercare_enrollment_step,
        aftercare_enrollment: enrollment,
        title: 'Hỏi thăm ngày 1',
        instructions: 'Hỏi khách trải nghiệm sau mua'
      )

      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :incoming, content: 'Em vừa mua xong')
      create(:message, account: account, inbox: inbox, conversation: conversation, message_type: :outgoing, content: 'Chúc mừng bạn đã đăng ký')

      with_modified_env(
        'CHATBOTLEVAN_INTERNAL_BASE_URL' => '',
        'CHATBOTLEVAN_BASE_URL' => 'http://chatbotlevan.local',
        'CHATBOTLEVAN_API_TOKEN' => 'aftercare-secret'
      ) do
        stub_request(:post, 'http://chatbotlevan.local/internal/aftercare/drafts')
          .with(headers: { 'Authorization' => 'Bearer aftercare-secret' })
          .to_return(
            status: 200,
            body: {
              draft_text: 'Chào bạn, mình hỏi thăm trải nghiệm sau buổi đầu nhé.',
              summary: 'Friendly day-1 check-in',
              version_fingerprint: 'draft-v1'
            }.to_json,
            headers: { 'Content-Type' => 'application/json' }
          )

        post(
          "/api/v1/accounts/#{account.id}/aftercare/enrollments/#{enrollment.id}/steps/#{step.id}/regenerate_draft",
          headers: administrator.create_new_auth_token
        )
      end

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:payload][:id]).to eq(step.id)
      expect(body[:payload][:draft_status]).to eq('ready')
      expect(body[:payload][:draft_body]).to eq('Chào bạn, mình hỏi thăm trải nghiệm sau buổi đầu nhé.')
      expect(body[:payload][:draft_summary]).to eq('Friendly day-1 check-in')
    end
  end

  describe 'POST /api/v1/accounts/:account_id/aftercare/enrollments/:enrollment_id/steps/:id/retry' do
    it 'retries the selected failed step and returns the updated payload' do
      enrollment = create(:aftercare_enrollment, account: account, created_by: administrator, status: :active)
      step = create(
        :aftercare_enrollment_step,
        aftercare_enrollment: enrollment,
        status: :failed,
        last_error: 'Temporary send failure'
      )

      post(
        "/api/v1/accounts/#{account.id}/aftercare/enrollments/#{enrollment.id}/steps/#{step.id}/retry",
        headers: administrator.create_new_auth_token
      )

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:payload][:id]).to eq(step.id)
      expect(body[:payload][:status]).to eq('scheduled')
      expect(step.reload.last_error).to be_blank
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/aftercare/enrollments/:enrollment_id/steps/:id' do
    it 'updates the selected step draft body and returns the refreshed payload' do
      enrollment = create(:aftercare_enrollment, account: account, created_by: administrator, status: :active)
      step = create(
        :aftercare_enrollment_step,
        aftercare_enrollment: enrollment,
        draft_status: :ready,
        draft_body: 'Bản nháp cũ',
        draft_error: 'Lỗi cũ'
      )

      patch(
        "/api/v1/accounts/#{account.id}/aftercare/enrollments/#{enrollment.id}/steps/#{step.id}",
        params: {
          draft_body: "Nội dung đã sửa thủ công\ncho khách"
        },
        headers: administrator.create_new_auth_token
      )

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:payload][:id]).to eq(step.id)
      expect(body[:payload][:draft_status]).to eq('ready')
      expect(body[:payload][:draft_body]).to eq("Nội dung đã sửa thủ công\ncho khách")

      step.reload
      expect(step.draft_body).to eq("Nội dung đã sửa thủ công\ncho khách")
      expect(step.draft_error).to be_blank
      expect(step.draft_generated_at).to be_present
    end
  end
end
