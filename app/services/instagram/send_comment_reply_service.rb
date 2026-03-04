# frozen_string_literal: true

class Instagram::SendCommentReplyService
  pattr_initialize [:message!]

  def perform
    return unless message.conversation.additional_attributes['type'] == 'instagram_comment'
    return if message.content.blank?

    send_reply
  end

  private

  def send_reply
    target_comment_id = find_target_comment_id
    unless target_comment_id
      Rails.logger.error(
        "[InstagramCommentReply] No target comment_id found: " \
        "message_id=#{message.id} conversation_id=#{message.conversation_id}"
      )
      Messages::StatusUpdateService.new(message, 'failed', 'No target comment_id for reply').perform
      return
    end

    access_token = channel_access_token
    unless access_token
      Rails.logger.error("[InstagramCommentReply] No access token for channel")
      Messages::StatusUpdateService.new(message, 'failed', 'No access token').perform
      return
    end

    response = HTTParty.post(
      "https://graph.instagram.com/v22.0/#{target_comment_id}/replies",
      body: { message: message.content },
      query: { access_token: access_token }
    )

    process_response(response)
  end

  def find_target_comment_id
    # V1: Reply to the root_comment_id stored in conversation attributes
    # This replies directly to the original comment on the post
    conversation = message.conversation
    conversation.additional_attributes['root_comment_id']
  end

  def process_response(response)
    parsed = response.parsed_response

    if response.success? && parsed['id'].present?
      message.update!(source_id: parsed['id'])
      Rails.logger.info(
        "[InstagramCommentReply] Success: message_id=#{message.id} " \
        "reply_id=#{parsed['id']} conversation_id=#{message.conversation_id}"
      )
    else
      error_msg = extract_error(parsed)
      Rails.logger.error(
        "[InstagramCommentReply] Failed: message_id=#{message.id} " \
        "error=#{error_msg} conversation_id=#{message.conversation_id}"
      )

      # Handle authorization errors
      error_code = parsed.dig('error', 'code')
      channel.authorization_error! if error_code == 190

      Messages::StatusUpdateService.new(message, 'failed', error_msg).perform
    end
  end

  def extract_error(parsed)
    error_message = parsed.dig('error', 'message') || 'Unknown error'
    error_code = parsed.dig('error', 'code') || 'unknown'
    "#{error_code} - #{error_message}"
  end

  def channel
    @channel ||= message.conversation.inbox.channel
  end

  def channel_access_token
    if channel.is_a?(Channel::Instagram)
      channel.access_token
    elsif channel.is_a?(Channel::FacebookPage)
      channel.page_access_token
    end
  end
end
