# frozen_string_literal: true

class Instagram::SendCommentReplyService
  pattr_initialize [:social_comment!, :reply_text!, :channel!]

  def perform
    send_reply
  end

  private

  def send_reply
    access_token = channel_access_token
    unless access_token
      raise StandardError, 'No access token available for this channel'
    end

    target_comment_id = social_comment.comment_id

    response = HTTParty.post(
      "https://graph.instagram.com/v22.0/#{target_comment_id}/replies",
      body: { message: reply_text, access_token: access_token }
    )

    if response.success?
      reply_id = response.parsed_response['id']

      unless reply_id.present?
        raise StandardError, "Instagram API did not return reply id. Response: #{response.body}"
      end

      # Create outgoing record in social_comments
      outgoing = SocialComment.new(
        account_id: social_comment.account_id,
        inbox_id: social_comment.inbox_id,
        platform: social_comment.platform,
        post_id: social_comment.post_id,
        comment_id: reply_id,
        parent_comment_id: target_comment_id,
        content: reply_text,
        author_name: 'Bot',
        direction: :outgoing,
        status: :replied,
        source_reply_id: reply_id,
        post_caption: social_comment.post_caption,
        post_media_url: social_comment.post_media_url,
        post_permalink: social_comment.post_permalink,
        post_like_count: social_comment.post_like_count,
        post_comment_count: social_comment.post_comment_count
      )

      unless outgoing.save
        raise StandardError, "Failed to save outgoing comment: #{outgoing.errors.full_messages.join(', ')}"
      end

      # Mark original comment as replied
      social_comment.update!(status: :replied)

      Rails.logger.info(
        "[InstagramCommentReply] Success: social_comment_id=#{social_comment.id} " \
        "reply_id=#{reply_id} outgoing_id=#{outgoing.id}"
      )

      { success: true, reply_id: reply_id, outgoing_id: outgoing.id }
    else
      error_body = response.body rescue response.parsed_response
      raise StandardError, "Instagram API error (#{response.code}): #{error_body}"
    end
  rescue StandardError => e
    Rails.logger.error(
      "[InstagramCommentReply] Error: #{e.message} " \
      "social_comment_id=#{social_comment.id}"
    )
    raise
  end

  def channel_access_token
    if channel.is_a?(Channel::Instagram)
      channel.access_token
    elsif channel.is_a?(Channel::FacebookPage)
      channel.page_access_token
    end
  end
end
