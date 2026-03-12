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
      let(:user) { create(:user, account: account, role: :administrator) }
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
      let(:user) { create(:user, account: account, role: :administrator) }

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

  describe 'GET /api/v1/accounts/{account.id}/ai_control/manager/*' do
    context 'when it is an authenticated user' do
      let(:user) { create(:user, account: account, role: :administrator) }
      let(:contact) { create(:contact, account: account, name: 'Tran Thi B') }
      let(:conversation) { create(:conversation, account: account, contact: contact) }

      it 'returns daily overview proxy data and enriches local conversation fields' do
        with_modified_env(
          'CHATBOTLEVAN_BASE_URL' => 'http://chatbotlevan.test',
          'CHATBOTLEVAN_API_TOKEN' => 'test-token'
        ) do
          stub_request(:get, 'http://chatbotlevan.test/tools/staff/daily-message-overview')
            .with(
              query: hash_including(
                'account_id' => account.id.to_s,
                'target_date' => '2026-03-12',
                'timezone_name' => 'Asia/Bangkok',
                'limit' => '5'
              ),
              headers: {
                'Authorization' => 'Bearer test-token'
              }
            )
            .to_return(
              status: 200,
              body: {
                ok: true,
                items: [
                  {
                    conversation_id: conversation.id.to_s,
                    topic_guess: 'dat lich',
                    message_count_in_day: 3
                  }
                ]
              }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          get "/api/v1/accounts/#{account.id}/ai_control/manager/daily_overview",
              headers: user.create_new_auth_token,
              params: { target_date: '2026-03-12', timezone_name: 'Asia/Bangkok', limit: 5 },
              as: :json

          expect(response).to have_http_status(:ok)
          json = response.parsed_body
          expect(json.dig('items', 0, 'conversation_display_id')).to eq(conversation.display_id)
          expect(json.dig('items', 0, 'contact_name')).to eq('Tran Thi B')
        end
      end

      it 'returns raw daily messages directly from Chatwoot DB grouped by conversation' do
        outgoing_user = create(:user, account: account, role: :administrator, name: 'Ops Lead')
        target_time = Time.find_zone('UTC').parse('2026-03-12 02:15:00')

        create(
          :message,
          account: account,
          inbox: conversation.inbox,
          conversation: conversation,
          sender: contact,
          message_type: :incoming,
          content: 'Em muốn hỏi về học phí khóa học hôm nay',
          created_at: target_time
        )
        create(
          :message,
          account: account,
          inbox: conversation.inbox,
          conversation: conversation,
          sender: outgoing_user,
          message_type: :outgoing,
          content: 'Bên mình đã nhận câu hỏi của bạn',
          created_at: target_time + 3.minutes
        )
        create(
          :message,
          account: account,
          inbox: conversation.inbox,
          conversation: conversation,
          sender: outgoing_user,
          message_type: :outgoing,
          private: true,
          content: 'Nhân viên note nội bộ',
          created_at: target_time + 5.minutes
        )

        get "/api/v1/accounts/#{account.id}/ai_control/manager/daily_raw_messages",
            headers: user.create_new_auth_token,
            params: { target_date: '2026-03-12', timezone_name: 'Asia/Bangkok' },
            as: :json

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['ok']).to eq(true)
        expect(json['target_date']).to eq('2026-03-12')
        expect(json['message_count']).to be >= 3
        expect(json['conversation_count']).to eq(1)
        expect(json.dig('conversations', 0, 'conversation_id')).to eq(conversation.id.to_s)
        expect(json.dig('conversations', 0, 'contact_name')).to eq('Tran Thi B')
        contents = json.dig('conversations', 0, 'messages').map { |item| item['content'] }
        incoming_row = json.dig('conversations', 0, 'messages').find { |item| item['content'] == 'Em muốn hỏi về học phí khóa học hôm nay' }
        private_row = json.dig('conversations', 0, 'messages').find { |item| item['content'] == 'Nhân viên note nội bộ' }
        expect(contents).to include('Em muốn hỏi về học phí khóa học hôm nay')
        expect(contents).to include('Bên mình đã nhận câu hỏi của bạn')
        expect(incoming_row['message_type']).to eq('incoming')
        expect(private_row['private']).to eq(true)
      end

      it 'returns bulk conversation messages grouped in one payload' do
        outgoing_user = create(:user, account: account, role: :administrator, name: 'Ops Lead')
        target_time = Time.find_zone('UTC').parse('2026-03-12 02:15:00')

        create(
          :message,
          account: account,
          inbox: conversation.inbox,
          conversation: conversation,
          sender: contact,
          message_type: :incoming,
          content: 'Em cần chị kiểm tra giúp đơn này',
          created_at: target_time
        )
        create(
          :message,
          account: account,
          inbox: conversation.inbox,
          conversation: conversation,
          sender: outgoing_user,
          message_type: :outgoing,
          content: 'Bên mình đã nhận thông tin của bạn',
          created_at: target_time + 3.minutes
        )

        post "/api/v1/accounts/#{account.id}/ai_control/manager/conversation_messages",
             headers: user.create_new_auth_token,
             params: {
               conversation_ids: [conversation.id.to_s],
               limit: 5
             },
             as: :json

        expect(response).to have_http_status(:ok)
        json = response.parsed_body
        expect(json['ok']).to eq(true)
        expect(json['conversation_count']).to eq(1)
        expect(json['limit_per_conversation']).to eq(5)
        expect(json['total_message_count']).to be >= 2
        rows = json.dig('messages_by_conversation', conversation.id.to_s)
        contents = rows.map { |item| item['content'] }
        expect(rows.length).to be >= 2
        expect(contents).to include('Em cần chị kiểm tra giúp đơn này')
        expect(contents).to include('Bên mình đã nhận thông tin của bạn')
      end

      it 'returns customer 360 proxy data and enriches contact metadata from chatwoot' do
        with_modified_env(
          'CHATBOTLEVAN_BASE_URL' => 'http://chatbotlevan.test',
          'CHATBOTLEVAN_API_TOKEN' => 'test-token'
        ) do
          stub_request(:get, 'http://chatbotlevan.test/tools/staff/customer-360')
            .with(
              query: hash_including(
                'account_id' => account.id.to_s,
                'conversation_id' => conversation.id.to_s,
                'memory_query' => 'paypal'
              ),
              headers: {
                'Authorization' => 'Bearer test-token'
              }
            )
            .to_return(
              status: 200,
              body: {
                ok: true,
                conversation_id: conversation.id.to_s,
                conversation: { labels: ['ai_handoff'] },
                contact_id: contact.id.to_s,
                contact_profile: {},
                memories: []
              }.to_json,
              headers: { 'Content-Type' => 'application/json' }
            )

          get "/api/v1/accounts/#{account.id}/ai_control/manager/customer_360",
              headers: user.create_new_auth_token,
              params: { conversation_id: conversation.id, memory_query: 'paypal' },
              as: :json

          expect(response).to have_http_status(:ok)
          json = response.parsed_body
          expect(json.dig('conversation', 'display_id')).to eq(conversation.display_id)
          expect(json.dig('contact_profile', 'name')).to eq('Tran Thi B')
        end
      end

      it 'returns unprocessable entity when manager customer 360 misses conversation_id' do
        get "/api/v1/accounts/#{account.id}/ai_control/manager/customer_360",
            headers: user.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('conversation_id is required')
      end
    end
  end

  describe 'POST /api/v1/accounts/{account.id}/ai_control/comments/:conversation_id/auto_reply' do
    context 'when it is an authenticated user' do
      let(:user) { create(:user, account: account, role: :administrator) }
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
      let(:user) { create(:user, account: account, role: :administrator) }

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
