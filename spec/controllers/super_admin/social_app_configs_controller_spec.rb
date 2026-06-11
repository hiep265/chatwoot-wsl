# frozen_string_literal: true

require 'rails_helper'

RSpec.describe SuperAdmin::SocialAppConfigsController, type: :controller do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }

  before { sign_in(super_admin) }

  describe 'GET #show' do
    it 'renders the show template with configs grouped by provider' do
      create(:account_social_app_config, account: account, provider: 'facebook', app_id: 'fb_123')
      get :show, params: { account_id: account.id }
      expect(response).to have_http_status(:success)
      expect(assigns(:configs)).to include('facebook')
    end
  end

  describe 'PATCH #update' do
    context 'with valid params' do
      it 'creates a new config for a provider' do
        expect {
          patch :update, params: {
            account_id: account.id,
            provider: 'facebook',
            social_app_config: { app_id: 'new_fb_id', app_secret: 'new_fb_secret' }
          }
        }.to change(AccountSocialAppConfig, :count).by(1)

        config = AccountSocialAppConfig.last
        expect(config.app_id).to eq('new_fb_id')
        expect(config.provider).to eq('facebook')
      end

      it 'updates an existing config' do
        config = create(:account_social_app_config, account: account, provider: 'facebook', app_id: 'old_id')
        patch :update, params: {
          account_id: account.id,
          provider: 'facebook',
          social_app_config: { app_id: 'new_id' }
        }
        config.reload
        expect(config.app_id).to eq('new_id')
      end

      it 'stores false human agent setting as a boolean' do
        patch :update, params: {
          account_id: account.id,
          provider: 'facebook',
          social_app_config: { enable_human_agent: 'false' }
        }

        config = AccountSocialAppConfig.find_by(account: account, provider: 'facebook')
        expect(config.settings['enable_human_agent']).to be false
      end

      it 'removes the human agent override when use global is selected' do
        config = create(:account_social_app_config, account: account, provider: 'facebook',
                                                    settings: { 'enable_human_agent' => true })

        patch :update, params: {
          account_id: account.id,
          provider: 'facebook',
          social_app_config: { enable_human_agent: '' }
        }

        config.reload
        expect(config.settings).not_to have_key('enable_human_agent')
      end
    end

    context 'with invalid provider' do
      it 'redirects with alert' do
        patch :update, params: {
          account_id: account.id,
          provider: 'invalid',
          social_app_config: { app_id: 'test' }
        }
        expect(response).to redirect_to(super_admin_account_social_app_config_path(account))
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe 'DELETE #destroy' do
    it 'removes a config' do
      config = create(:account_social_app_config, account: account, provider: 'facebook')
      expect {
        delete :destroy, params: { account_id: account.id, provider: 'facebook' }
      }.to change(AccountSocialAppConfig, :count).by(-1)
    end
  end
end
