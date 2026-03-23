# frozen_string_literal: true

class AiControl::CommentWebhookDispatchService
  pattr_initialize [:social_comment!]

  def perform
    webhook_url = resolve_comment_webhook_url
    if webhook_url.blank?
      Rails.logger.info(
        "[AiControl] comment_webhook_skip social_comment_id=#{social_comment.id} account_id=#{social_comment.account_id} reason=missing_webhook_url"
      )
      return false
    end

    WebhookJob.perform_later(webhook_url, webhook_payload)

    Rails.logger.info(
      "[AiControl] comment_webhook_enqueued social_comment_id=#{social_comment.id} account_id=#{social_comment.account_id} webhook_url=#{webhook_url}"
    )
    true
  end

  private

  def resolve_comment_webhook_url
    account_url = ::Redis::Alfred.get(comment_webhook_url_redis_key).to_s.strip
    return account_url.chomp('/') if account_url.present?

    env_url = ENV.fetch('CHATBOTLEVAN_COMMENT_WEBHOOK_URL', '').to_s.strip
    return env_url.chomp('/') if env_url.present?

    base_url = ChatbotlevanEndpointResolver.chatbotlevan_base_url
    return '' if base_url.blank?

    "#{base_url}/webhooks/chatwoot/comments"
  end

  def comment_webhook_url_redis_key
    "ai_control:comment_webhook_url:#{social_comment.account_id}"
  end

  def webhook_payload
    {
      event: 'social_comment_created',
      social_comment: {
        id: social_comment.id,
        comment_id: social_comment.comment_id,
        content: social_comment.content,
        author_name: social_comment.author_name,
        post_id: social_comment.post_id,
        post_caption: social_comment.post_caption,
        platform: social_comment.platform,
        inbox_id: social_comment.inbox_id,
        account_id: social_comment.account_id
      }
    }
  end
end
