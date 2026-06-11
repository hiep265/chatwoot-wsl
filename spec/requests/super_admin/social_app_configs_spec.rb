# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Super Admin Social App Configs', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }

  describe 'GET /super_admin/accounts/:account_id/social_app_config' do
    context 'when unauthenticated' do
      it 'redirects to sign in' do
        get super_admin_account_social_app_config_path(account)
        expect(response).to redirect_to(new_super_admin_session_path)
      end
    end

    context 'when authenticated as super admin' do
      before { sign_in(super_admin, scope: :super_admin) }

      it 'shows the social app config page' do
        get super_admin_account_social_app_config_path(account)
        expect(response).to have_http_status(:success)
      end
    end
  end

  describe 'PATCH /super_admin/accounts/:account_id/social_app_config' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'creates a new social app config' do
      expect {
        patch super_admin_account_social_app_config_path(account), params: {
          provider: 'facebook',
          social_app_config: { app_id: 'test_fb_id', app_secret: 'test_fb_secret' }
        }
      }.to change(AccountSocialAppConfig, :count).by(1)
    end

    it 'updates an existing config' do
      create(:account_social_app_config, account: account, provider: 'facebook', app_id: 'old_id')
      patch super_admin_account_social_app_config_path(account), params: {
        provider: 'facebook',
        social_app_config: { app_id: 'new_id' }
      }
      expect(AccountSocialAppConfig.find_by(account: account, provider: 'facebook').app_id).to eq('new_id')
    end
  end

  describe 'DELETE /super_admin/accounts/:account_id/social_app_config' do
    before { sign_in(super_admin, scope: :super_admin) }

    it 'deletes a social app config' do
      config = create(:account_social_app_config, account: account, provider: 'tiktok')
      expect {
        delete super_admin_account_social_app_config_path(account), params: { provider: 'tiktok' }
      }.to change(AccountSocialAppConfig, :count).by(-1)
    end
  end
end
