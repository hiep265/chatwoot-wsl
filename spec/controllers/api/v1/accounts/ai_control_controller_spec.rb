require 'rails_helper'

RSpec.describe 'AiControlController', type: :request do
  let(:account) { create(:account) }
  let(:comment_webhook_config_key) { "ai_control:comment_webhook_url:#{account.id}" }

  after do
    begin
      ::Redis::Alfred.delete(comment_webhook_config_key)
    rescue StandardError
      nil
    end
  end

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

  describe 'POST /api/v1/accounts/{account.id}/ai_control/comments/:conversation_id/auto_reply' do
    context 'when it is an authenticated user' do
      let(:user) { create(:user, account: account) }
      let(:inbox) { create(:inbox, account: account) }
      let(:social_comment) do
        SocialComment.create!(
          account: account,
          inbox: inbox,
          platform: 'instagram',
          post_id: 'post_001',
          comment_id: "comment_#{rand(100_000)}",
          content: 'Ban oi cho minh xin thong tin khoa hoc',
          author_name: 'Demo User',
          author_id: 'ig_user_1',
          direction: :incoming,
          status: :pending
        )
      end

      it 'uses CHATBOTLEVAN_COMMENT_WEBHOOK_URL when configured' do
        with_modified_env(
          'CHATBOTLEVAN_COMMENT_WEBHOOK_URL' => 'http://chatbotlevan.test/webhooks/chatwoot/comments',
          'CHATBOTLEVAN_BASE_URL' => ''
        ) do
          expect(WebhookJob).to receive(:perform_later).with(
            'http://chatbotlevan.test/webhooks/chatwoot/comments',
            hash_including(
              event: 'social_comment_created',
              social_comment: hash_including(
                id: social_comment.id,
                account_id: account.id
              )
            )
          ).once

          post "/api/v1/accounts/#{account.id}/ai_control/comments/#{social_comment.id}/auto_reply",
               headers: user.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:ok)
          json = response.parsed_body
          expect(json['status']).to eq('triggered')
          expect(json['webhook_url']).to eq('http://chatbotlevan.test/webhooks/chatwoot/comments')
        end
      end

      it 'falls back to CHATBOTLEVAN_BASE_URL/comments webhook when comment webhook env is empty' do
        with_modified_env(
          'CHATBOTLEVAN_COMMENT_WEBHOOK_URL' => '',
          'CHATBOTLEVAN_BASE_URL' => 'http://chatbotlevan.test'
        ) do
          expect(WebhookJob).to receive(:perform_later).with(
            'http://chatbotlevan.test/webhooks/chatwoot/comments',
            hash_including(event: 'social_comment_created')
          ).once

          post "/api/v1/accounts/#{account.id}/ai_control/comments/#{social_comment.id}/auto_reply",
               headers: user.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:ok)
          json = response.parsed_body
          expect(json['webhook_url']).to eq('http://chatbotlevan.test/webhooks/chatwoot/comments')
        end
      end

      it 'prefers comment_webhook_url from request payload over env config' do
        with_modified_env(
          'CHATBOTLEVAN_COMMENT_WEBHOOK_URL' => 'http://chatbotlevan.test/webhooks/chatwoot/comments',
          'CHATBOTLEVAN_BASE_URL' => 'http://chatbotlevan.test'
        ) do
          expect(WebhookJob).to receive(:perform_later).with(
            'https://custom-comment-hook.local/webhooks/chatwoot/comments',
            hash_including(event: 'social_comment_created')
          ).once

          post "/api/v1/accounts/#{account.id}/ai_control/comments/#{social_comment.id}/auto_reply",
               headers: user.create_new_auth_token,
               params: { comment_webhook_url: 'https://custom-comment-hook.local/webhooks/chatwoot/comments' },
               as: :json

          expect(response).to have_http_status(:ok)
          json = response.parsed_body
          expect(json['webhook_url']).to eq('https://custom-comment-hook.local/webhooks/chatwoot/comments')
        end
      end

      it 'returns unprocessable entity when both comment webhook and base url are missing' do
        with_modified_env(
          'CHATBOTLEVAN_COMMENT_WEBHOOK_URL' => '',
          'CHATBOTLEVAN_BASE_URL' => ''
        ) do
          expect(WebhookJob).not_to receive(:perform_later)

          post "/api/v1/accounts/#{account.id}/ai_control/comments/#{social_comment.id}/auto_reply",
               headers: user.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:unprocessable_entity)
          json = response.parsed_body
          expect(json['error']).to eq('CHATBOTLEVAN comment webhook is not configured')
        end
      end

      it 'uses comment webhook configured in integrations settings (redis) when request and env are empty' do
        with_modified_env(
          'CHATBOTLEVAN_COMMENT_WEBHOOK_URL' => '',
          'CHATBOTLEVAN_BASE_URL' => ''
        ) do
          ::Redis::Alfred.set(comment_webhook_config_key, 'https://integrations.local/webhooks/chatwoot/comments')

          expect(WebhookJob).to receive(:perform_later).with(
            'https://integrations.local/webhooks/chatwoot/comments',
            hash_including(event: 'social_comment_created')
          ).once

          post "/api/v1/accounts/#{account.id}/ai_control/comments/#{social_comment.id}/auto_reply",
               headers: user.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:ok)
          json = response.parsed_body
          expect(json['webhook_url']).to eq('https://integrations.local/webhooks/chatwoot/comments')
        end
      end
    end
  end

  describe 'GET/PUT /api/v1/accounts/{account.id}/ai_control/comment_webhook_config' do
    context 'when it is an authenticated user' do
      let(:user) { create(:user, account: account) }

      it 'saves and returns comment webhook config' do
        put "/api/v1/accounts/#{account.id}/ai_control/comment_webhook_config",
            headers: user.create_new_auth_token,
            params: { comment_webhook_url: 'https://example.local/webhooks/chatwoot/comments/' },
            as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['comment_webhook_url']).to eq('https://example.local/webhooks/chatwoot/comments')

        get "/api/v1/accounts/#{account.id}/ai_control/comment_webhook_config",
            headers: user.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body['comment_webhook_url']).to eq('https://example.local/webhooks/chatwoot/comments')
      end

      it 'returns unprocessable entity for invalid comment webhook url' do
        put "/api/v1/accounts/#{account.id}/ai_control/comment_webhook_config",
            headers: user.create_new_auth_token,
            params: { comment_webhook_url: 'not-a-url' },
            as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to include('comment_webhook_url')
      end
    end
  end
end
