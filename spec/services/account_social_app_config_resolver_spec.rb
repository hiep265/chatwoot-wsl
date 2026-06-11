# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AccountSocialAppConfigResolver do
  let(:account) { create(:account) }

  describe '#load' do
    context 'when account has an override config' do
      before do
        create(:account_social_app_config, account: account, provider: 'facebook',
                                          app_id: 'custom_fb_id', app_secret: 'custom_fb_secret')
      end

      it 'returns account-level value for mapped config key' do
        resolver = described_class.new(account)
        expect(resolver.load('FB_APP_ID', '')).to eq('custom_fb_id')
      end

      it 'returns account-level secret value' do
        resolver = described_class.new(account)
        expect(resolver.load('FB_APP_SECRET', '')).to eq('custom_fb_secret')
      end

      it 'falls back to global config for unmapped key' do
        resolver = described_class.new(account)
        expect(resolver.load('WHATSAPP_APP_ID', '')).to eq('')
      end
    end

    context 'when account has no override config' do
      it 'falls back to GlobalConfigService' do
        allow(GlobalConfigService).to receive(:load).with('FB_APP_ID', '').and_return('global_fb_id')
        resolver = described_class.new(account)
        expect(resolver.load('FB_APP_ID', '')).to eq('global_fb_id')
      end
    end

    context 'when account config has blank value for a field' do
      before do
        create(:account_social_app_config, account: account, provider: 'facebook', app_id: '')
      end

      it 'falls back to global config for blank values' do
        allow(GlobalConfigService).to receive(:load).with('FB_APP_ID', 'default').and_return('global_fb_id')
        resolver = described_class.new(account)
        expect(resolver.load('FB_APP_ID', 'default')).to eq('global_fb_id')
      end
    end

    context 'when account is nil' do
      it 'falls back to global config' do
        allow(GlobalConfigService).to receive(:load).with('FB_APP_ID', '').and_return('global_fb_id')
        resolver = described_class.new(nil)
        expect(resolver.load('FB_APP_ID', '')).to eq('global_fb_id')
      end
    end

    context 'settings-based values' do
      before do
        create(:account_social_app_config, account: account, provider: 'facebook',
                                          settings: { 'enable_human_agent' => true })
      end

      it 'resolves enable_human_agent from settings jsonb' do
        resolver = described_class.new(account)
        expect(resolver.load('ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT', nil)).to eq(true)
      end
    end

    context 'when account config explicitly disables a boolean setting' do
      before do
        create(:account_social_app_config, account: account, provider: 'facebook',
                                          settings: { 'enable_human_agent' => false })
      end

      it 'returns false instead of falling back to the global value' do
        allow(GlobalConfigService).to receive(:load).with('ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT', nil).and_return(true)

        resolver = described_class.new(account)
        expect(resolver.load('ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT', nil)).to eq(false)
      end
    end
  end

  describe '#load_many' do
    before do
      create(:account_social_app_config, account: account, provider: 'facebook',
                                        app_id: 'custom_fb_id', app_secret: 'custom_fb_secret')
    end

    it 'resolves multiple keys at once' do
      resolver = described_class.new(account)
      result = resolver.load_many('FB_APP_ID' => '', 'FB_APP_SECRET' => '')
      expect(result['FB_APP_ID']).to eq('custom_fb_id')
      expect(result['FB_APP_SECRET']).to eq('custom_fb_secret')
    end
  end

  describe 'field mapping coverage' do
    AccountSocialAppConfigResolver::MAPPING.each do |config_key, mapping|
      it "maps #{config_key} to #{mapping[:provider]}.#{mapping[:field]}" do
        provider = mapping[:provider]
        field = mapping[:field]
        create(:account_social_app_config, account: account, provider: provider,
                                          field => 'test_value') unless mapping[:settings]
        if mapping[:settings]
          config = AccountSocialAppConfig.find_or_initialize_by(account: account, provider: provider)
          config.settings = { field.to_s => 'test_value' }
          config.save!
        end
        resolver = described_class.new(account)
        expect(resolver.load(config_key, '')).to eq('test_value')
      end
    end
  end
end
