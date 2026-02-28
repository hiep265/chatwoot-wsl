require 'rails_helper'

RSpec.describe 'AiControlController', type: :request do
  let(:account) { create(:account) }

  describe 'GET /api/v1/accounts/{account.id}/ai_control/payment_review_cases' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/ai_control/payment_review_cases", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:user) { create(:user, account: account) }
      let(:contact) { create(:contact, account: account, name: 'Nguyen Van A') }
      let(:conversation) { create(:conversation, account: account, contact: contact) }

      it 'returns payment review queue from chatbotlevan' do
        with_modified_env(
          'CHATBOTLEVAN_BASE_URL' => 'http://chatbotlevan.test',
          'CHATBOTLEVAN_API_TOKEN' => 'test-token'
        ) do
          stub_request(:get, 'http://chatbotlevan.test/tools/payment-review-cases')
            .with(
              query: {
                'review_status' => 'payment_review_pending',
                'segment' => 'online_course',
                'limit' => '20',
                'offset' => '0'
              },
              headers: {
                'Authorization' => 'Bearer test-token'
              }
            )
            .to_return(
              status: 200,
              body: {
                success: true,
                total: 1,
                count: 1,
                cases: [
                  {
                    id: 'case-001',
                    conversation_id: conversation.id.to_s,
                    chat_excerpt: 'Em da thanh toan roi',
                    review_status: 'payment_review_pending',
                    segment: 'online_course'
                  }
                ]
              }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          get "/api/v1/accounts/#{account.id}/ai_control/payment_review_cases",
              headers: user.create_new_auth_token,
              params: { segment: 'online_course', limit: 20, offset: 0 },
              as: :json

          expect(response).to have_http_status(:ok)
          json = response.parsed_body
          expect(json['success']).to eq(true)
          expect(json['total']).to eq(1)
          expect(json.dig('cases', 0, 'chat_excerpt')).to eq('Em da thanh toan roi')
          expect(json.dig('cases', 0, 'contact_name')).to eq('Nguyen Van A')
          expect(json.dig('cases', 0, 'conversation_display_id')).to eq(conversation.display_id)
        end
      end

      it 'returns unprocessable entity if CHATBOTLEVAN_BASE_URL is missing' do
        with_modified_env('CHATBOTLEVAN_BASE_URL' => '') do
          get "/api/v1/accounts/#{account.id}/ai_control/payment_review_cases",
              headers: user.create_new_auth_token,
              as: :json

          expect(response).to have_http_status(:unprocessable_entity)
          json = response.parsed_body
          expect(json['error']).to eq('CHATBOTLEVAN_BASE_URL is not configured')
        end
      end

      it 'returns bad gateway when chatbotlevan responds with error' do
        with_modified_env(
          'CHATBOTLEVAN_BASE_URL' => 'http://chatbotlevan.test',
          'CHATBOTLEVAN_API_TOKEN' => 'test-token'
        ) do
          stub_request(:get, 'http://chatbotlevan.test/tools/payment-review-cases')
            .with(
              query: hash_including('review_status' => 'payment_review_pending'),
              headers: {
                'Authorization' => 'Bearer test-token'
              }
            )
            .to_return(
              status: 500,
              body: { error: 'db down' }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          get "/api/v1/accounts/#{account.id}/ai_control/payment_review_cases",
              headers: user.create_new_auth_token,
              as: :json

          expect(response).to have_http_status(:bad_gateway)
          json = response.parsed_body
          expect(json['error']).to eq('Payment review queue request failed')
        end
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/ai_control/payment_review_cases/:case_id/review' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/ai_control/payment_review_cases/case-001/review",
             params: { review_action: 'confirm' },
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated user' do
      let(:user) { create(:user, account: account) }

      it 'forwards review action to chatbotlevan' do
        with_modified_env(
          'CHATBOTLEVAN_BASE_URL' => 'http://chatbotlevan.test',
          'CHATBOTLEVAN_API_TOKEN' => 'test-token'
        ) do
          stub_request(:post, 'http://chatbotlevan.test/tools/payment-review-cases/case-001/review')
            .with(
              headers: { 'Authorization' => 'Bearer test-token' },
              body: hash_including(
                'review_action' => 'confirm'
              )
            )
            .to_return(
              status: 200,
              body: {
                success: true,
                review_action: 'confirm',
                case: { id: 'case-001', review_status: 'payment_verified_manual' }
              }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          post "/api/v1/accounts/#{account.id}/ai_control/payment_review_cases/case-001/review",
               headers: user.create_new_auth_token,
               params: { review_action: 'confirm', review_note: 'ok' },
               as: :json

          expect(response).to have_http_status(:ok)
          json = response.parsed_body
          expect(json['success']).to eq(true)
          expect(json.dig('case', 'review_status')).to eq('payment_verified_manual')
        end
      end

      it 'returns unprocessable entity when review_action is invalid' do
        post "/api/v1/accounts/#{account.id}/ai_control/payment_review_cases/case-001/review",
             headers: user.create_new_auth_token,
             params: { review_action: 'invalid_action' },
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        json = response.parsed_body
        expect(json['error']).to eq('review_action is invalid')
      end
    end
  end
end
