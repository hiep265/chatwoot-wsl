class Webhooks::InstagramController < ActionController::API
  include MetaTokenVerifyConcern

  def events
    Rails.logger.info('Instagram webhook received events')
    if params['object'].casecmp('instagram').zero?
      entry_params = params.to_unsafe_hash[:entry]

      # Split entries: comment events vs messaging (DM) events
      comment_entries, messaging_entries = split_comment_and_messaging_entries(entry_params)

      # Dispatch comment entries to the dedicated comment job
      if comment_entries.present?
        Rails.logger.info("[InstagramWebhook] Dispatching #{comment_entries.size} comment entries")
        ::Webhooks::InstagramCommentEventsJob.perform_later(comment_entries)
      end

      # Dispatch messaging entries to the existing DM job
      if messaging_entries.present?
        if contains_echo_event?(messaging_entries)
          # Add delay to prevent race condition where echo arrives before send message API completes
          ::Webhooks::InstagramEventsJob.set(wait: 2.seconds).perform_later(messaging_entries)
        else
          ::Webhooks::InstagramEventsJob.perform_later(messaging_entries)
        end
      end

      render json: :ok
    else
      Rails.logger.warn("Message is not received from the instagram webhook event: #{params['object']}")
      head :unprocessable_entity
    end
  end

  private

  # Separate comment entries (changes with field=comments) from messaging entries (DM/standby).
  # An entry with `changes` where field == "comments" is a comment event.
  # An entry with `messaging` or `standby` is a DM event.
  # An entry with `changes` where field == "messages" is a test event (handled by DM job).
  def split_comment_and_messaging_entries(entry_params)
    return [[], []] unless entry_params.is_a?(Array)

    comment_entries = []
    messaging_entries = []

    entry_params.each do |entry|
      entry = entry.with_indifferent_access if entry.respond_to?(:with_indifferent_access)

      if comment_entry?(entry)
        comment_entries << entry
      else
        messaging_entries << entry
      end
    end

    [comment_entries, messaging_entries]
  end

  # An entry is a comment entry if it has `changes` with at least one change where field == "comments"
  def comment_entry?(entry)
    return false unless entry[:changes].present?

    entry[:changes].any? { |change| change[:field] == 'comments' }
  end

  def contains_echo_event?(entry_params)
    return false unless entry_params.is_a?(Array)

    entry_params.any? do |entry|
      # Check messaging array for echo events
      messaging_events = entry[:messaging] || []
      messaging_events.any? { |messaging| messaging.dig(:message, :is_echo).present? }
    end
  end

  def valid_token?(token)
    # Validates against both IG_VERIFY_TOKEN (Instagram channel via Facebook page) and
    # INSTAGRAM_VERIFY_TOKEN (Instagram channel via direct Instagram login)
    token == GlobalConfigService.load('IG_VERIFY_TOKEN', '') ||
      token == GlobalConfigService.load('INSTAGRAM_VERIFY_TOKEN', '')
  end
end
