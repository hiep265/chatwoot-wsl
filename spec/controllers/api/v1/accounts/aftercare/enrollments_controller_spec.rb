require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Aftercare::EnrollmentsController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  before do
    stub_request(:post, /graph.facebook.com/)
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
    allow(Facebook::Messenger::Subscriptions).to receive(:unsubscribe).and_return(true)
    GlobalConfig.clear_cache
    clear_enqueued_jobs
  end

  describe 'POST /api/v1/accounts/:account_id/aftercare/enrollments' do
    it 'creates an enrollment, syncs contact email, clones steps, and enqueues the opt-in and draft generation jobs' do
      sequence = AftercareSequence.create!(
        code: 'post_purchase_checkin_controller_spec',
        name: 'Chăm sóc sau mua',
        opt_in_topic: 'aftercare.post_purchase_checkin_controller_spec',
        active: true
      )
      sequence.aftercare_sequence_steps.create!(
        position: 1,
        title: 'Hỏi thăm',
        instructions: 'Hỏi khách sau mua',
        offset_minutes: 1440,
        enabled: true
      )

      facebook_channel = create(:channel_facebook_page, account: account)
      inbox = create(:inbox, account: account, channel: facebook_channel)
      conversation = create(:conversation, account: account, inbox: inbox)
      conversation.contact.update!(email: nil)
      create(:message, account: account, inbox: inbox, conversation: conversation, created_at: 2.hours.ago)

      expect do
        post "/api/v1/accounts/#{account.id}/aftercare/enrollments",
             headers: administrator.create_new_auth_token,
             params: {
               conversation_id: conversation.id,
               sequence_id: sequence.id,
               contact_email: 'lan.aftercare@example.com',
               staff_note: 'Khách vừa mua gói cơ bản',
               timezone_name: 'Asia/Bangkok',
               anchor_at: Time.current.iso8601,
               steps: [
                 {
                   position: 1,
                   scheduled_for: 1.day.from_now.iso8601,
                   enabled: true,
                   step_note: 'Nhấn mạnh cách dùng tuần đầu'
                 }
               ]
             }
      end.to have_enqueued_job(Aftercare::RequestOptInJob)
        .and have_enqueued_job(Aftercare::GenerateStepDraftJob)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:payload][:status]).to eq('pending_optin')
      expect(body[:payload][:contact][:email]).to eq('lan.aftercare@example.com')
      expect(body[:payload][:steps].length).to eq(1)
      expect(body[:payload][:opt_in_subscription][:status]).to eq('not_requested')
      expect(body[:payload][:steps].first[:draft_status]).to eq('not_requested')
      expect(conversation.contact.reload.email).to eq('lan.aftercare@example.com')
    end

    it 'accepts a conversation display_id in the API payload' do
      sequence = AftercareSequence.create!(
        code: 'post_purchase_checkin_controller_display_id_spec',
        name: 'Chăm sóc sau mua',
        opt_in_topic: 'aftercare.post_purchase_checkin_controller_display_id_spec',
        active: true
      )
      sequence.aftercare_sequence_steps.create!(
        position: 1,
        title: 'Hỏi thăm',
        instructions: 'Hỏi khách sau mua',
        offset_minutes: 1440,
        enabled: true
      )

      facebook_channel = create(:channel_facebook_page, account: account)
      inbox = create(:inbox, account: account, channel: facebook_channel)
      conversation = create(:conversation, account: account, inbox: inbox)
      display_id = 2_000_000_000
      conversation.update_column(:display_id, display_id)
      create(:message, account: account, inbox: inbox, conversation: conversation, created_at: 2.hours.ago)

      post "/api/v1/accounts/#{account.id}/aftercare/enrollments",
           headers: administrator.create_new_auth_token,
           params: {
             conversation_id: display_id,
             sequence_id: sequence.id,
             timezone_name: 'Asia/Bangkok',
             anchor_at: Time.current.iso8601
           }

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:payload][:conversation][:display_id]).to eq(display_id)
    end

    it 'creates dynamic payload steps beyond the seeded sequence length' do
      sequence = AftercareSequence.create!(
        code: 'post_purchase_dynamic_payload_steps_spec',
        name: 'Chăm sóc sau mua động',
        opt_in_topic: 'aftercare.post_purchase_dynamic_payload_steps_spec',
        active: true
      )
      sequence.aftercare_sequence_steps.create!(
        position: 1,
        title: 'Seed step 1',
        instructions: 'Seed instruction 1',
        offset_minutes: 1440,
        enabled: true
      )

      facebook_channel = create(:channel_facebook_page, account: account)
      inbox = create(:inbox, account: account, channel: facebook_channel)
      conversation = create(:conversation, account: account, inbox: inbox)
      create(:message, account: account, inbox: inbox, conversation: conversation, created_at: 2.hours.ago)

      post "/api/v1/accounts/#{account.id}/aftercare/enrollments",
           headers: administrator.create_new_auth_token,
           params: {
             conversation_id: conversation.id,
             sequence_id: sequence.id,
             timezone_name: 'Asia/Bangkok',
             anchor_at: '2026-03-21T10:00:00Z',
             steps: [
               {
                 position: 1,
                 title: 'Bước 1',
                 instructions: 'Instruction 1',
                 scheduled_for: '2026-03-21T10:00:00Z',
                 enabled: true
               },
               {
                 position: 2,
                 title: 'Bước 2',
                 instructions: 'Instruction 2',
                 scheduled_for: '2026-03-31T10:00:00Z',
                 enabled: true
               },
               {
                 position: 3,
                 title: 'Bước 3',
                 instructions: 'Instruction 3',
                 offset_minutes: 28800,
                 enabled: true
               }
             ]
           }

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:payload][:steps].length).to eq(3)
      expect(body[:payload][:steps].map { |step| step[:position] }).to eq([1, 2, 3])
      expect(body[:payload][:steps].map { |step| step[:title] }).to eq(['Bước 1', 'Bước 2', 'Bước 3'])
    end
  end

  describe 'GET /api/v1/accounts/:account_id/aftercare/enrollments' do
    it 'returns enrollments ordered by newest first' do
      older = AftercareEnrollment.create!(
        account: account,
        conversation: create(:conversation, account: account),
        contact: create(:contact, account: account),
        inbox: create(:inbox, account: account),
        aftercare_sequence: AftercareSequence.create!(
          code: 'older_sequence',
          name: 'Older',
          opt_in_topic: 'aftercare.older',
          active: true
        ),
        created_by: administrator,
        channel_type: 'Channel::FacebookPage',
        channel_key: 'messenger',
        status: :draft,
        timezone_name: 'Asia/Bangkok',
        anchor_at: 2.days.ago
      )
      newer = AftercareEnrollment.create!(
        account: account,
        conversation: create(:conversation, account: account),
        contact: create(:contact, account: account),
        inbox: create(:inbox, account: account),
        aftercare_sequence: AftercareSequence.create!(
          code: 'newer_sequence',
          name: 'Newer',
          opt_in_topic: 'aftercare.newer',
          active: true
        ),
        created_by: administrator,
        channel_type: 'Channel::FacebookPage',
        channel_key: 'messenger',
        status: :pending_optin,
        timezone_name: 'Asia/Bangkok',
        anchor_at: Time.current
      )

      older.update_column(:created_at, 2.days.ago)
      newer.update_column(:created_at, Time.current)

      get "/api/v1/accounts/#{account.id}/aftercare/enrollments",
          headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:payload].map { |item| item[:id] }).to eq([newer.id, older.id])
    end
  end

  describe 'POST /api/v1/accounts/:account_id/aftercare/enrollments/:id/cancel' do
    it 'cancels the selected enrollment and returns the updated payload' do
      enrollment = create(:aftercare_enrollment, account: account, created_by: administrator, status: :active)
      create(:aftercare_enrollment_step, aftercare_enrollment: enrollment, status: :scheduled)

      post "/api/v1/accounts/#{account.id}/aftercare/enrollments/#{enrollment.id}/cancel",
           headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:payload][:id]).to eq(enrollment.id)
      expect(body[:payload][:status]).to eq('cancelled')
      expect(enrollment.reload.status).to eq('cancelled')
    end
  end

  describe 'POST /api/v1/accounts/:account_id/aftercare/enrollments/:id/pause' do
    it 'pauses an active enrollment and returns the updated payload' do
      enrollment = create(:aftercare_enrollment, account: account, created_by: administrator, status: :active)

      post "/api/v1/accounts/#{account.id}/aftercare/enrollments/#{enrollment.id}/pause",
           headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:payload][:status]).to eq('paused')
      expect(enrollment.reload.status).to eq('paused')
    end
  end

  describe 'POST /api/v1/accounts/:account_id/aftercare/enrollments/:id/resume' do
    it 'resumes a paused enrollment and returns the updated payload' do
      enrollment = create(
        :aftercare_enrollment,
        account: account,
        created_by: administrator,
        status: :paused,
        paused_at: 10.minutes.ago
      )
      enrollment.create_aftercare_opt_in_subscription!(
        topic: enrollment.aftercare_sequence.opt_in_topic,
        provider: 'meta',
        capability_status: 'supported',
        status: :subscribed,
        token_ref: 'resume-token'
      )

      post "/api/v1/accounts/#{account.id}/aftercare/enrollments/#{enrollment.id}/resume",
           headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:payload][:status]).to eq('active')
      expect(enrollment.reload.status).to eq('active')
    end
  end
end
