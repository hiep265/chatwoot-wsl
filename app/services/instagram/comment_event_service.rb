# frozen_string_literal: true

class Instagram::CommentEventService
  pattr_initialize [:comment_data!, :channel!]

  REDIS_DEDUPE_TTL = 7.days.to_i

  def perform
    @comment_id = comment_data[:id]
    @text = comment_data[:text]
    @from = comment_data[:from] || {}
    @media_id = comment_data.dig(:media, :id)
    @parent_id = comment_data[:parent_id]
    @timestamp = comment_data[:created_time] || comment_data[:timestamp]

    return if duplicate_comment?

    create_social_comment
    mark_comment_seen
    fetch_post_metadata if @social_comment.present? && @media_id.present?
    dispatch_comment_webhook if @social_comment.present?
  rescue StandardError => e
    Rails.logger.error(
      "[InstagramComment] Service error: #{e.message} " \
      "comment_id=#{@comment_id} account_id=#{inbox&.account_id}"
    )
    raise
  end

  private

  def duplicate_comment?
    redis_key = "social_comment:seen:instagram:#{@comment_id}"

    # Check Redis first (fast path)
    if ::Redis::Alfred.get(redis_key).present?
      Rails.logger.info("[InstagramComment] Dedupe hit (Redis): comment_id=#{@comment_id}")
      return true
    end

    # Fallback: check DB unique index
    if SocialComment.exists?(comment_id: @comment_id)
      Rails.logger.info("[InstagramComment] Dedupe hit (DB): comment_id=#{@comment_id}")
      mark_comment_seen
      return true
    end

    false
  end

  def mark_comment_seen
    redis_key = "social_comment:seen:instagram:#{@comment_id}"
    ::Redis::Alfred.setex(redis_key, REDIS_DEDUPE_TTL, '1')
  end

  def create_social_comment
    @social_comment = SocialComment.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      platform: 'instagram',
      post_id: @media_id.to_s,
      comment_id: @comment_id,
      parent_comment_id: @parent_id,
      content: @text,
      author_name: @from[:username] || 'Instagram User',
      author_id: @from[:id],
      direction: :incoming,
      status: :pending
    )

    Rails.logger.info(
      "[InstagramComment] Created social_comment: " \
      "id=#{@social_comment.id} comment_id=#{@comment_id} " \
      "post_id=#{@media_id} account_id=#{inbox.account_id}"
    )
  end

  def fetch_post_metadata
    access_token = channel_access_token
    return unless access_token.present?

    begin
      response = HTTParty.get(
        "https://graph.instagram.com/v22.0/#{@media_id}",
        query: {
          fields: 'caption,media_url,like_count,comments_count,permalink,timestamp',
          access_token: access_token
        }
      )

      if response.success?
        data = response.parsed_response
        # Update this comment and all other comments for the same post
        SocialComment.where(account_id: inbox.account_id, post_id: @media_id.to_s)
                     .update_all(
                       post_caption: data['caption'],
                       post_media_url: data['media_url'],
                       post_like_count: data['like_count'],
                       post_comment_count: data['comments_count'],
                       post_permalink: data['permalink']
                     )
        Rails.logger.info("[InstagramComment] Fetched post metadata: post_id=#{@media_id}")
      else
        Rails.logger.warn(
          "[InstagramComment] Failed to fetch post metadata: post_id=#{@media_id} " \
          "status=#{response.code} body=#{response.body}"
        )
      end
    rescue StandardError => e
      Rails.logger.error("[InstagramComment] Graph API error: #{e.message} post_id=#{@media_id}")
    end
  end

  def dispatch_comment_webhook
    AiControl::CommentWebhookDispatchService.new(
      social_comment: @social_comment
    ).perform
  rescue StandardError => e
    Rails.logger.error(
      "[InstagramComment] Auto webhook dispatch failed: #{e.message} " \
      "social_comment_id=#{@social_comment&.id} account_id=#{inbox&.account_id}"
    )
  end

  def channel_access_token
    if channel.is_a?(Channel::Instagram)
      channel.access_token
    elsif channel.is_a?(Channel::FacebookPage)
      channel.page_access_token
    end
  end

  def inbox
    @inbox ||= channel.inbox
  end
end
