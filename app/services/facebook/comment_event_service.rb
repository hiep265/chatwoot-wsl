# frozen_string_literal: true

class Facebook::CommentEventService
  pattr_initialize [:comment_data!, :channel!]

  REDIS_DEDUPE_TTL = 7.days.to_i

  def perform
    @comment_id = comment_data[:id]
    @text = comment_data[:message]
    @from = comment_data[:from] || {}
    @post_id = comment_data.dig(:post, :id) || extract_post_id_from_comment_id
    @parent_id = comment_data[:parent_id] || comment_data[:parent_comment]
    @timestamp = comment_data[:created_time]

    return if duplicate_comment?

    create_social_comment
    mark_comment_seen
    fetch_post_metadata if @social_comment.present? && @post_id.present?
    dispatch_comment_webhook if @social_comment.present?
  rescue StandardError => e
    Rails.logger.error(
      "[FacebookComment] Service error: #{e.message} " \
      "comment_id=#{@comment_id} account_id=#{inbox&.account_id}"
    )
    raise
  end

  private

  def extract_post_id_from_comment_id
    return nil unless @comment_id.present?

    parts = @comment_id.split("_")
    parts.length > 1 ? parts.first : @comment_id
  end

  def duplicate_comment?
    redis_key = "social_comment:seen:facebook:#{@comment_id}"

    if ::Redis::Alfred.get(redis_key).present?
      Rails.logger.info("[FacebookComment] Dedupe hit (Redis): comment_id=#{@comment_id}")
      return true
    end

    if SocialComment.exists?(comment_id: @comment_id)
      Rails.logger.info("[FacebookComment] Dedupe hit (DB): comment_id=#{@comment_id}")
      mark_comment_seen
      return true
    end

    false
  end

  def mark_comment_seen
    redis_key = "social_comment:seen:facebook:#{@comment_id}"
    ::Redis::Alfred.setex(redis_key, REDIS_DEDUPE_TTL, "1")
  end

  def create_social_comment
    @social_comment = SocialComment.create!(
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      platform: "facebook",
      post_id: @post_id.to_s,
      comment_id: @comment_id,
      parent_comment_id: @parent_id,
      content: @text,
      author_name: @from[:name] || "Facebook User",
      author_id: @from[:id],
      direction: :incoming,
      status: :pending
    )

    Rails.logger.info(
      "[FacebookComment] Created social_comment: " \
      "id=#{@social_comment.id} comment_id=#{@comment_id} " \
      "post_id=#{@post_id} account_id=#{inbox.account_id}"
    )
  end

  def fetch_post_metadata
    access_token = channel.page_access_token
    return unless access_token.present?

    begin
      response = HTTParty.get(
        "https://graph.facebook.com/v22.0/#{@post_id}",
        query: {
          fields: "message,full_picture,likes.summary(true),comments.summary(true),permalink_url,created_time",
          access_token: access_token
        }
      )

      if response.success?
        data = response.parsed_response
        like_count = data.dig("likes", "summary", "total_count") rescue 0
        comment_count = data.dig("comments", "summary", "total_count") rescue 0

        SocialComment.where(account_id: inbox.account_id, post_id: @post_id.to_s)
                     .update_all(
                       post_caption: data["message"],
                       post_media_url: data["full_picture"],
                       post_like_count: like_count,
                       post_comment_count: comment_count,
                       post_permalink: data["permalink_url"]
                     )
        Rails.logger.info("[FacebookComment] Fetched post metadata: post_id=#{@post_id}")
      else
        Rails.logger.warn(
          "[FacebookComment] Failed to fetch post metadata: post_id=#{@post_id} " \
          "status=#{response.code} body=#{response.body}"
        )
      end
    rescue StandardError => e
      Rails.logger.error("[FacebookComment] Graph API error: #{e.message} post_id=#{@post_id}")
    end
  end

  def dispatch_comment_webhook
    AiControl::CommentWebhookDispatchService.new(
      social_comment: @social_comment
    ).perform
  rescue StandardError => e
    Rails.logger.error(
      "[FacebookComment] Auto webhook dispatch failed: #{e.message} " \
      "social_comment_id=#{@social_comment&.id} account_id=#{inbox&.account_id}"
    )
  end

  def inbox
    @inbox ||= channel.inbox
  end
end
