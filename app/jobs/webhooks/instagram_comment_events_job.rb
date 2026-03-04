# frozen_string_literal: true

class Webhooks::InstagramCommentEventsJob < ApplicationJob
  queue_as :default

  def perform(entries)
    entries.each do |entry|
      process_comment_entry(entry.with_indifferent_access)
    end
  end

  private

  def process_comment_entry(entry)
    ig_account_id = entry[:id]
    changes = entry[:changes] || []

    changes.each do |change|
      next unless change[:field] == 'comments'

      comment_data = change[:value]
      next if comment_data.blank?

      channel = find_channel(ig_account_id)
      unless channel
        Rails.logger.warn(
          "[InstagramComment] No channel found for instagram_id=#{ig_account_id}"
        )
        next
      end

      process_single_comment(comment_data, channel)
    end
  end

  def process_single_comment(comment_data, channel)
    Instagram::CommentEventService.new(
      comment_data: comment_data,
      channel: channel
    ).perform
  rescue StandardError => e
    Rails.logger.error(
      "[InstagramComment] Error processing comment: #{e.message} " \
      "comment_id=#{comment_data&.dig(:id)} " \
      "channel_id=#{channel&.id}"
    )
    ChatwootExceptionTracker.new(e, account: channel&.account).capture_exception
  end

  def find_channel(instagram_id)
    Channel::Instagram.find_by(instagram_id: instagram_id) ||
      Channel::FacebookPage.find_by(instagram_id: instagram_id)
  end
end
