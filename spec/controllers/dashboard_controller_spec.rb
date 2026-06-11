require 'rails_helper'

describe '/app/login', type: :request do
  context 'without DEFAULT_LOCALE' do
    it 'renders the dashboard' do
      get '/app/login'
      expect(response).to have_http_status(:success)
    end
  end

  context 'with DEFAULT_LOCALE' do
    it 'renders the dashboard' do
      with_modified_env DEFAULT_LOCALE: 'pt_BR' do
        get '/app/login'
        expect(response).to have_http_status(:success)
        expect(response.body).to include "selectedLocale: 'pt_BR'"
      end
    end
  end

  context 'with non-HTML format' do
    it 'returns not acceptable for JSON with error message' do
      get '/app/login', headers: { 'Accept' => 'application/json' }
      expect(response).to have_http_status(:not_acceptable)
      expect(response.parsed_body).to eq({ 'error' => 'Please use API routes instead of dashboard routes for JSON requests' })
    end
  end

  # Routes are loaded once on app start
  # hence Rails.application.reload_routes! is used in this spec
  # ref : https://stackoverflow.com/a/63584877/939299
  context 'with CW_API_ONLY_SERVER true' do
    it 'returns 404' do
      with_modified_env CW_API_ONLY_SERVER: 'true' do
        Rails.application.reload_routes!
        get '/app/login'
        expect(response).to have_http_status(:not_found)
      end
      Rails.application.reload_routes!
    end
  end
end

describe '/app/accounts/:account_id/settings/inboxes/new/instagram', type: :request do
  let(:account) { create(:account) }

  before do
    create(
      :account_social_app_config,
      account: account,
      provider: 'facebook',
      app_id: 'account-fb-app-id',
      api_version: 'v99.0'
    )
    create(
      :account_social_app_config,
      account: account,
      provider: 'whatsapp_embedded',
      app_id: 'account-wa-app-id',
      configuration_id: 'account-wa-config-id',
      api_version: 'v98.0'
    )
  end

  it 'renders account-scoped social app config in chatwootConfig' do
    get "/app/accounts/#{account.id}/settings/inboxes/new/instagram"

    expect(response).to have_http_status(:success)
    expect(response.body).to include("fbAppId: 'account-fb-app-id'")
    expect(response.body).to include("fbApiVersion: 'v99.0'")
    expect(response.body).to include("whatsappAppId: 'account-wa-app-id'")
    expect(response.body).to include("whatsappConfigurationId: 'account-wa-config-id'")
    expect(response.body).to include("whatsappApiVersion: 'v98.0'")
  end
end
