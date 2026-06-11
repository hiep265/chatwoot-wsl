require 'rails_helper'

RSpec.describe Tiktok::IntegrationHelper do
  include described_class

  describe '#generate_tiktok_token' do
    let(:account) { create(:account) }

    before do
      allow(GlobalConfigService).to receive(:load).with('TIKTOK_APP_SECRET', nil).and_return(nil)
      create(:account_social_app_config, account: account, provider: 'tiktok', app_secret: 'account_tiktok_secret')
    end

    it 'signs the state token with the account-level secret' do
      token = generate_tiktok_token(account.id)
      decoded_token = JWT.decode(token, 'account_tiktok_secret', true, algorithm: 'HS256').first

      expect(decoded_token['sub']).to eq(account.id)
    end
  end

  describe '#verify_tiktok_token' do
    let(:account) { create(:account) }
    let(:token) { JWT.encode({ sub: account.id, iat: Time.current.to_i }, 'account_tiktok_secret', 'HS256') }

    before do
      allow(GlobalConfigService).to receive(:load).with('TIKTOK_APP_SECRET', nil).and_return(nil)
      create(:account_social_app_config, account: account, provider: 'tiktok', app_secret: 'account_tiktok_secret')
    end

    it 'verifies the token with the account-level secret' do
      expect(verify_tiktok_token(token)).to eq(account.id)
    end
  end
end
