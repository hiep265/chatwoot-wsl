# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiControl::CommentWebhookDispatchService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:social_comment) do
    SocialComment.create!(
      account: account,
      inbox: inbox,
      platform: 'instagram',
      post_id: 'post_001',
      comment_id: "comment_#{rand(100_000)}",
      content: 'auto webhook test',
      author_name: 'test_user',
      author_id: 'ig_user_1',
      direction: :incoming,
      status: :pending
    )
  end
  let(:service) { described_class.new(social_comment: social_comment) }
  let(:redis_key) { "ai_control:comment_webhook_url:#{account.id}" }

  after do
    ::Redis::Alfred.delete(redis_key)
  end

  describe '#perform' do
    it 'uses account-specific webhook url from redis first' do
      ::Redis::Alfred.set(redis_key, 'https://account.local/webhooks/chatwoot/comments/')

      expect(WebhookJob).to receive(:perform_later).with(
        'https://account.local/webhooks/chatwoot/comments',
        hash_including(
          event: 'social_comment_created',
          social_comment: hash_including(
            id: social_comment.id,
            account_id: account.id
          )
        )
      ).once

      expect(service.perform).to eq(true)
    end

    it 'falls back to CHATBOTLEVAN_COMMENT_WEBHOOK_URL' do
      with_modified_env(
        'CHATBOTLEVAN_COMMENT_WEBHOOK_URL' => 'https://env.local/webhooks/chatwoot/comments',
        'CHATBOTLEVAN_BASE_URL' => ''
      ) do
        expect(WebhookJob).to receive(:perform_later).with(
          'https://env.local/webhooks/chatwoot/comments',
          hash_including(event: 'social_comment_created')
        ).once

        expect(service.perform).to eq(true)
      end
    end

    it 'falls back to CHATBOTLEVAN_BASE_URL when specific comment webhook env is empty' do
      with_modified_env(
        'CHATBOTLEVAN_COMMENT_WEBHOOK_URL' => '',
        'CHATBOTLEVAN_BASE_URL' => 'https://base.local'
      ) do
        expect(WebhookJob).to receive(:perform_later).with(
          'https://base.local/webhooks/chatwoot/comments',
          hash_including(event: 'social_comment_created')
        ).once

        expect(service.perform).to eq(true)
      end
    end

    it 'skips dispatch when no webhook url can be resolved' do
      with_modified_env(
        'CHATBOTLEVAN_COMMENT_WEBHOOK_URL' => '',
        'CHATBOTLEVAN_BASE_URL' => ''
      ) do
        expect(WebhookJob).not_to receive(:perform_later)
        expect(service.perform).to eq(false)
      end
    end
  end
end
