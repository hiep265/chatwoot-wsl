# frozen_string_literal: true

class Instagram::CommentEventService
  pattr_initialize [:comment_data!, :channel!]

  REDIS_DEDUPE_TTL = 7.days.to_i
  COMMENT_TYPES = %w[instagram_comment].freeze

  def perform
    @comment_id = comment_data[:id]
    @text = comment_data[:text]
    @from = comment_data[:from] || {}
    @media_id = comment_data.dig(:media, :id)
    @parent_id = comment_data[:parent_id]
    @timestamp = comment_data[:created_time] || comment_data[:timestamp]

    return if duplicate_comment?

    ActiveRecord::Base.transaction do
      find_or_create_contact
      find_or_create_conversation
      create_message
    end

    mark_comment_seen
    fetch_post_metadata_async if @conversation_is_new
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

    # Fallback: check DB
    if Message.exists?(source_id: @comment_id, inbox_id: inbox.id)
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

  def find_or_create_contact
    sender_ig_id = @from[:id] || @from[:username] || "unknown_#{@comment_id}"
    sender_name = @from[:username] || "Instagram User"

    contact_inbox = inbox.contact_inboxes.find_by(source_id: sender_ig_id)

    if contact_inbox
      @contact = contact_inbox.contact
    else
      @contact = inbox.account.contacts.create!(
        name: sender_name,
        additional_attributes: {
          social_instagram_user_name: @from[:username]
        }
      )
      @contact_inbox = inbox.contact_inboxes.create!(
        contact: @contact,
        source_id: sender_ig_id
      )
    end
  end

  def find_or_create_conversation
    # Find existing conversation for this post+contact
    @conversation = Conversation
      .where(inbox_id: inbox.id, contact_id: @contact.id)
      .where("additional_attributes->>'type' = ?", 'instagram_comment')
      .where("additional_attributes->>'post_id' = ?", @media_id.to_s)
      .where.not(status: :resolved)
      .order(created_at: :desc)
      .first

    if @conversation
      @conversation_is_new = false
    else
      contact_inbox = @contact_inbox || inbox.contact_inboxes.find_by!(contact: @contact)
      @conversation = Conversation.create!(
        account_id: inbox.account_id,
        inbox_id: inbox.id,
        contact_id: @contact.id,
        contact_inbox_id: contact_inbox.id,
        additional_attributes: conversation_additional_attributes
      )
      @conversation_is_new = true
    end
  end

  def create_message
    @message = @conversation.messages.create!(
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      message_type: :incoming,
      content: @text,
      source_id: @comment_id,
      sender: @contact,
      content_attributes: message_content_attributes
    )

    Rails.logger.info(
      "[InstagramComment] Created message: " \
      "message_id=#{@message.id} comment_id=#{@comment_id} " \
      "conversation_id=#{@conversation.id} account_id=#{inbox.account_id}"
    )
  end

  def conversation_additional_attributes
    {
      type: 'instagram_comment',
      platform: 'instagram',
      post_id: @media_id.to_s,
      root_comment_id: @parent_id || @comment_id
    }
  end

  def message_content_attributes
    {
      is_social_comment: true,
      platform: 'instagram',
      comment_id: @comment_id,
      parent_comment_id: @parent_id,
      actor_id: @from[:id],
      actor_name: @from[:username],
      is_bot_generated: false
    }
  end

  def fetch_post_metadata_async
    # Fetch post details from Graph API and update conversation attributes.
    # Done inline for simplicity in V1; can be moved to a background job later.
    access_token = channel_access_token
    return unless access_token.present? && @media_id.present?

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
        @conversation.update!(
          additional_attributes: @conversation.additional_attributes.merge(
            post_caption: data['caption'],
            post_media_url: data['media_url'],
            post_like_count: data['like_count'],
            post_comment_count: data['comments_count'],
            post_permalink: data['permalink']
          )
        )
        Rails.logger.info(
          "[InstagramComment] Fetched post metadata: post_id=#{@media_id} " \
          "conversation_id=#{@conversation.id}"
        )
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
