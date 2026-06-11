# frozen_string_literal: true

class Webhooks::FacebookCommentEventsJob < ApplicationJob
  queue_as :default

  def perform(entries)
    entries.each do |entry|
      process_comment_entry(entry.with_indifferent_access)
    end
  end

  private

  def process_comment_entry(entry)
    page_id = entry[:id]
    changes = entry[:changes] || []

    changes.each do |change|
      next unless change[:field] == "feed"

      value = change[:value]
      next if value.blank?

      # Facebook page feed changes include posts, comments, reactions, etc.
      # We only process comment events
      item = value[:item]
      verb = value[:verb]

      next unless item == "comment" && verb != "remove"

      channel = find_channel(page_id)
      unless channel
        Rails.logger.warn(
          "[FacebookComment] No channel found for page_id=#{page_id}"
        )
        next
      end

      comment_data = build_comment_data(value, page_id)
      process_single_comment(comment_data, channel)
    end
  end

  def build_comment_data(value, page_id)
    {
      id: value[:comment_id],
      message: value[:message],
      from: value[:from] || {},
      post: { id: value[:post_id] || value[:parent_id] },
      parent_id: value[:parent_id] || value[:reply_parent_comment_id],
      created_time: value[:created_time],
      verb: value[:verb]
    }
  end

  def process_single_comment(comment_data, channel)
    Facebook::CommentEventService.new(
      comment_data: comment_data,
      channel: channel
    ).perform
  rescue StandardError => e
    Rails.logger.error(
      "[FacebookComment] Error processing comment: #{e.message} " \
      "comment_id=#{comment_data&.dig(:id)} " \
      "channel_id=#{channel&.id}"
    )
    ChatwootExceptionTracker.new(e, account: channel&.account).capture_exception
  end

  def find_channel(page_id)
    Channel::FacebookPage.find_by(page_id: page_id)
  end
end
