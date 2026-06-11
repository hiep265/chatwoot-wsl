# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountSocialAppConfig do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
  end

  describe 'validations' do
    it 'validates provider inclusion' do
      config = build(:account_social_app_config, provider: 'invalid_provider')
      expect(config).not_to be_valid
      expect(config.errors[:provider]).to include('is not included in the list')
    end

    it 'validates uniqueness of provider scoped to account' do
      account = create(:account)
      create(:account_social_app_config, account: account, provider: 'facebook')
      duplicate = build(:account_social_app_config, account: account, provider: 'facebook')
      expect(duplicate).not_to be_valid
    end

    it 'allows same provider for different accounts' do
      account1 = create(:account)
      account2 = create(:account)
      create(:account_social_app_config, account: account1, provider: 'facebook')
      config2 = build(:account_social_app_config, account: account2, provider: 'facebook')
      expect(config2).to be_valid
    end

    AccountSocialAppConfig::PROVIDERS.each do |provider|
      it "allows #{provider} as a valid provider" do
        config = build(:account_social_app_config, provider: provider)
        expect(config).to be_valid
      end
    end
  end

  describe 'store_accessor for settings' do
    it 'stores enable_human_agent in settings jsonb' do
      config = create(:account_social_app_config, provider: 'facebook', settings: { 'enable_human_agent' => true })
      expect(config.enable_human_agent).to eq(true)
    end
  end
end
