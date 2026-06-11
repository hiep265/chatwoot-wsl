require 'rails_helper'

RSpec.describe 'Instagram Authorization API', type: :request do
  let(:account) { create(:account) }

  describe 'POST /api/v1/accounts/{account.id}/instagram/authorization' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/instagram/authorization"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:agent) { create(:user, account: account, role: :agent) }
      let(:administrator) { create(:user, account: account, role: :administrator) }

      it 'returns unauthorized for agent' do
        post "/api/v1/accounts/#{account.id}/instagram/authorization",
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end

      it 'creates a new authorization and returns the redirect url' do
        post "/api/v1/accounts/#{account.id}/instagram/authorization",
             headers: administrator.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body['success']).to be true

        authorization_url = URI.parse(response.parsed_body['url'])
        authorization_params = Rack::Utils.parse_query(authorization_url.query)

        expect(authorization_url.host).to eq('www.instagram.com')
        expect(authorization_url.path).to eq('/oauth/authorize')
        expect(authorization_params).to include(
          'redirect_uri' => "#{ENV.fetch('FRONTEND_URL', 'http://localhost:3000')}/instagram/callback",
          'scope' => Instagram::IntegrationHelper::REQUIRED_SCOPES.join(','),
          'enable_fb_login' => '0',
          'force_reauth' => '1',
          'response_type' => 'code'
        )
        expect(authorization_params).not_to include('force_authentication')
      end
    end
  end
end
