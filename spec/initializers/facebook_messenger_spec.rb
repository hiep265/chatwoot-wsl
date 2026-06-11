require 'rails_helper'

RSpec.describe ChatwootFbProvider do
  describe '#valid_verify_token?' do
    let(:account) { create(:account) }

    before do
      allow(GlobalConfigService).to receive(:load).with('FB_VERIFY_TOKEN', '').and_return('global_verify_token')
      create(:account_social_app_config, account: account, provider: 'facebook', verify_token: 'account_verify_token')
    end

    it 'accepts account-level Facebook verify tokens' do
      expect(described_class.new.valid_verify_token?('account_verify_token')).to be true
    end

    it 'accepts the global fallback Facebook verify token' do
      expect(described_class.new.valid_verify_token?('global_verify_token')).to be true
    end

    it 'rejects unknown Facebook verify tokens' do
      expect(described_class.new.valid_verify_token?('unknown')).to be false
    end
  end
end
