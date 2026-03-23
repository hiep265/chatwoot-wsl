require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Aftercare::EligibilityController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  before do
    stub_request(:post, /graph.facebook.com/)
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
    allow(Facebook::Messenger::Subscriptions).to receive(:unsubscribe).and_return(true)
    GlobalConfig.clear_cache
  end

  describe 'GET /api/v1/accounts/:account_id/aftercare/eligibility' do
    it 'returns eligible for a recent messenger conversation' do
      facebook_channel = create(:channel_facebook_page, account: account)
      inbox = create(:inbox, account: account, channel: facebook_channel)
      conversation = create(:conversation, account: account, inbox: inbox)
      create(:message, account: account, inbox: inbox, conversation: conversation, created_at: 2.hours.ago)

      get "/api/v1/accounts/#{account.id}/aftercare/eligibility",
          headers: administrator.create_new_auth_token,
          params: { conversation_id: conversation.id }

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:eligible]).to be(true)
      expect(body[:channel_key]).to eq('messenger')
      expect(body[:reason_code]).to eq('eligible')
    end

    it 'returns blocked for unsupported channels' do
      inbox = create(:inbox, account: account)
      conversation = create(:conversation, account: account, inbox: inbox)

      get "/api/v1/accounts/#{account.id}/aftercare/eligibility",
          headers: administrator.create_new_auth_token,
          params: { conversation_id: conversation.id }

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:eligible]).to be(false)
      expect(body[:reason_code]).to eq('unsupported_channel')
    end
  end
end
