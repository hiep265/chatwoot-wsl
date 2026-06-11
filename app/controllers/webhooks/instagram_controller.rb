class Webhooks::InstagramController < ActionController::API
  include MetaTokenVerifyConcern

  def events
    Rails.logger.info("Instagram webhook received events: object=#{params["object"]}")

    if params["object"].casecmp("instagram").zero?
      handle_instagram_events
    elsif params["object"].casecmp("page").zero?
      handle_facebook_page_events
    else
      Rails.logger.warn("Message is not received from the instagram webhook event: #{params["object"]}")
      head :unprocessable_entity
    end
  end

  private

  def handle_instagram_events
    entry_params = params.to_unsafe_hash[:entry]

    comment_entries, messaging_entries = split_comment_and_messaging_entries(entry_params)

    if comment_entries.present?
      Rails.logger.info("[InstagramWebhook] Dispatching #{comment_entries.size} comment entries")
      ::Webhooks::InstagramCommentEventsJob.perform_later(comment_entries)
    end

    if messaging_entries.present?
      if contains_echo_event?(messaging_entries)
        ::Webhooks::InstagramEventsJob.set(wait: 2.seconds).perform_later(messaging_entries)
      else
        ::Webhooks::InstagramEventsJob.perform_later(messaging_entries)
      end
    end

    render json: :ok
  end

  def handle_facebook_page_events
    entry_params = params.to_unsafe_hash[:entry]
    return render json: :ok unless entry_params.is_a?(Array)

    comment_entries = []
    messaging_entries = []

    entry_params.each do |entry|
      entry = entry.with_indifferent_access if entry.respond_to?(:with_indifferent_access)

      if facebook_comment_entry?(entry)
        comment_entries << entry
      else
        messaging_entries << entry
      end
    end

    if comment_entries.present?
      Rails.logger.info("[FacebookPageWebhook] Dispatching #{comment_entries.size} comment entries")
      ::Webhooks::FacebookCommentEventsJob.perform_later(comment_entries)
    end

    if messaging_entries.present?
      Rails.logger.info("[FacebookPageWebhook] Skipping #{messaging_entries.size} messaging entries (handled by /bot)")
    end

    render json: :ok
  end

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

  def comment_entry?(entry)
    return false unless entry[:changes].present?

    entry[:changes].any? { |change| change[:field] == "comments" }
  end

  def facebook_comment_entry?(entry)
    return false unless entry[:changes].present?

    entry[:changes].any? do |change|
      change[:field] == "feed" &&
        change.dig(:value, :item) == "comment"
    end
  end

  def contains_echo_event?(entry_params)
    return false unless entry_params.is_a?(Array)

    entry_params.any? do |entry|
      messaging_events = entry[:messaging] || []
      messaging_events.any? { |messaging| messaging.dig(:message, :is_echo).present? }
    end
  end

  def valid_token?(token)
    global_tokens = [
      GlobalConfigService.load("IG_VERIFY_TOKEN", ""),
      GlobalConfigService.load("INSTAGRAM_VERIFY_TOKEN", ""),
      GlobalConfigService.load("FB_VERIFY_TOKEN", "")
    ]
    account_tokens = AccountSocialAppConfig.where(provider: %w[instagram facebook]).filter_map(&:verify_token)

    (global_tokens + account_tokens).include?(token)
  end
end
