require 'rails_helper'

RSpec.describe InstagramConcern do
  let(:dummy_class) { Class.new { include InstagramConcern } }
  let(:dummy_instance) { dummy_class.new }
  let(:client_id) { 'test_client_id' }
  let(:client_secret) { 'test_client_secret' }
  let(:short_lived_token) { 'short_lived_token' }
  let(:long_lived_token) { 'long_lived_token' }
  let(:access_token) { 'access_token' }

  before do
    allow(GlobalConfigService).to receive(:load).with('INSTAGRAM_APP_ID', nil).and_return(client_id)
    allow(GlobalConfigService).to receive(:load).with('INSTAGRAM_APP_SECRET', nil).and_return(client_secret)
    allow(Rails.logger).to receive(:error)
  end

  describe '#instagram_client' do
    it 'creates an OAuth2 client with correct configuration', :aggregate_failures do
      client = dummy_instance.instagram_client

      expect(client).to be_a(OAuth2::Client)
      expect(client.id).to eq(client_id)
      expect(client.secret).to eq(client_secret)
      expect(client.site).to eq('https://api.instagram.com')
      expect(client.options[:authorize_url]).to eq('https://www.instagram.com/oauth/authorize')
      expect(client.options[:token_url]).to eq('https://api.instagram.com/oauth/access_token')
      expect(client.options[:auth_scheme]).to eq(:request_body)
      expect(client.options[:token_method]).to eq(:post)
    end

    context 'when Current.account is blank and the controller exposes an account' do
      let(:account) { create(:account) }
      let(:dummy_class) do
        Class.new do
          include InstagramConcern

          attr_writer :account

          private

          def account
            @account
          end
        end
      end

      before do
        Current.account = nil
        dummy_instance.account = account
        create(
          :account_social_app_config,
          account: account,
          provider: 'instagram',
          app_id: 'account_instagram_id',
          app_secret: 'account_instagram_secret'
        )
      end

      it 'uses the callback account social app config', :aggregate_failures do
        client = dummy_instance.instagram_client

        expect(client.id).to eq('account_instagram_id')
        expect(client.secret).to eq('account_instagram_secret')
      end
    end
  end

  describe '#exchange_for_long_lived_token' do
    let(:response_body) { { 'access_token' => long_lived_token, 'expires_in' => 5_184_000 }.to_json }
    let(:mock_response) { instance_double(HTTParty::Response, body: response_body, success?: true) }

    before do
      allow(HTTParty).to receive(:get).and_return(mock_response)
      allow(mock_response).to receive(:inspect).and_return(response_body)
    end

    it 'exchanges short lived token for long lived token' do
      result = dummy_instance.send(:exchange_for_long_lived_token, short_lived_token)

      expect(HTTParty).to have_received(:get).with(
        'https://graph.instagram.com/access_token',
        {
          query: {
            grant_type: 'ig_exchange_token',
            client_secret: client_secret,
            access_token: short_lived_token
          },
          headers: { 'Accept' => 'application/json' }
        }
      )

      expect(result).to eq({ 'access_token' => long_lived_token, 'expires_in' => 5_184_000 })
    end

    context 'when the request fails' do
      let(:mock_response) { instance_double(HTTParty::Response, body: 'Error', success?: false, code: 400) }

      it 'raises an error' do
        expect do
          dummy_instance.send(:exchange_for_long_lived_token, short_lived_token)
        end.to raise_error(RuntimeError, 'Failed to exchange token: Error')
      end
    end

    context 'when the response is not valid JSON' do
      let(:mock_response) { instance_double(HTTParty::Response, body: 'Not JSON', success?: true) }

      it 'raises a JSON parse error' do
        allow(JSON).to receive(:parse).and_raise(JSON::ParserError.new('Invalid JSON'))

        expect { dummy_instance.send(:exchange_for_long_lived_token, short_lived_token) }.to raise_error(JSON::ParserError)
      end
    end

    context 'when Instagram rejects the long-lived token request' do
      let(:unsupported_get_response) do
        instance_double(
          HTTParty::Response,
          body: {
            error: {
              message: 'Unsupported request - method type: get',
              type: 'IGApiException',
              code: 100
            }
          }.to_json,
          success?: false,
          code: 400
        )
      end

      before do
        allow(HTTParty).to receive(:get).and_return(unsupported_get_response)
      end

      it 'raises the GET response without retrying with POST' do
        expect(HTTParty).not_to receive(:post)

        expect do
          dummy_instance.send(:exchange_for_long_lived_token, short_lived_token)
        end.to raise_error(RuntimeError, /Unsupported request - method type: get/)

        expect(HTTParty).to have_received(:get).with(
          'https://graph.instagram.com/access_token',
          {
            query: {
              grant_type: 'ig_exchange_token',
              client_secret: client_secret,
              access_token: short_lived_token
            },
            headers: { 'Accept' => 'application/json' }
          }
        )
      end
    end
  end

  describe '#fetch_instagram_user_details' do
    let(:user_details) do
      {
        'id' => '12345',
        'username' => 'test_user',
        'user_id' => '12345',
        'name' => 'Test User',
        'profile_picture_url' => 'https://example.com/profile.jpg',
        'account_type' => 'BUSINESS'
      }
    end
    let(:response_body) { user_details.to_json }
    let(:mock_response) { instance_double(HTTParty::Response, body: response_body, success?: true) }

    before do
      allow(HTTParty).to receive(:get).and_return(mock_response)
      allow(mock_response).to receive(:inspect).and_return(response_body)
    end

    it 'fetches Instagram user details' do
      result = dummy_instance.send(:fetch_instagram_user_details, access_token)

      expect(HTTParty).to have_received(:get).with(
        'https://graph.instagram.com/v22.0/me',
        {
          query: {
            fields: 'id,username,user_id,name,profile_picture_url,account_type',
            access_token: access_token
          },
          headers: { 'Accept' => 'application/json' }
        }
      )

      expect(result).to eq(user_details)
    end

    context 'when the request fails' do
      let(:mock_response) { instance_double(HTTParty::Response, body: 'Error', success?: false, code: 400) }

      it 'raises an error' do
        expect do
          dummy_instance.send(:fetch_instagram_user_details, access_token)
        end.to raise_error(RuntimeError, 'Failed to fetch Instagram user details: Error')
      end
    end

    context 'when the response is not valid JSON' do
      let(:mock_response) { instance_double(HTTParty::Response, body: 'Not JSON', success?: true) }

      it 'raises a JSON parse error' do
        allow(JSON).to receive(:parse).and_raise(JSON::ParserError.new('Invalid JSON'))

        expect { dummy_instance.send(:fetch_instagram_user_details, access_token) }.to raise_error(JSON::ParserError)
      end
    end
  end
end
