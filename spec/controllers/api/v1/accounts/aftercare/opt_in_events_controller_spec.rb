require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Aftercare::OptInEventsController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  describe 'POST /api/v1/accounts/:account_id/aftercare/opt_in_events' do
    it 'activates the enrollment when the opt-in subscription becomes subscribed' do
      sequence_code = "post_purchase_checkin_#{SecureRandom.hex(4)}"
      sequence = AftercareSequence.create!(
        code: sequence_code,
        name: 'Chăm sóc sau mua',
        opt_in_topic: "aftercare.#{sequence_code}",
        active: true
      )
      enrollment = AftercareEnrollment.create!(
        account: account,
        conversation: create(:conversation, account: account),
        contact: create(:contact, account: account),
        inbox: create(:inbox, account: account),
        aftercare_sequence: sequence,
        created_by: administrator,
        channel_type: 'Channel::FacebookPage',
        channel_key: 'messenger',
        status: :pending_optin,
        timezone_name: 'Asia/Bangkok',
        anchor_at: Time.current
      )
      subscription = AftercareOptInSubscription.create!(
        aftercare_enrollment: enrollment,
        topic: sequence.opt_in_topic,
        status: :requested,
        provider: 'meta',
        capability_status: 'supported'
      )

      post "/api/v1/accounts/#{account.id}/aftercare/opt_in_events",
           headers: administrator.create_new_auth_token,
           params: {
             subscription_id: subscription.id,
             event_name: 'opt_in.subscribed',
             token_ref: 'meta-token-123',
             occurred_at: Time.current.iso8601,
             expires_at: 30.days.from_now.iso8601,
             payload: { source: 'meta_webhook' }
           }

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:payload][:subscription_status]).to eq('subscribed')
      expect(body[:payload][:enrollment_status]).to eq('active')
    end
  end
end
