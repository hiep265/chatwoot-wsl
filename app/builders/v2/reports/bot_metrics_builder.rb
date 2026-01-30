class V2::Reports::BotMetricsBuilder
  include DateRangeHelper
  attr_reader :account, :params

  def initialize(account, params)
    @account = account
    @params = params
  end

  def metrics
    payload = {
      conversation_count: bot_conversations.count,
      message_count: bot_messages.count,
      resolution_rate: bot_resolution_rate.to_i,
      handoff_rate: bot_handoff_rate.to_i
    }

    if debug? || env_debug?
      debug = debug_payload
      payload[:debug] = debug if debug?
      log_debug(debug)
    end
    payload
  end

  private

  def bot_activated_inbox_ids
    @bot_activated_inbox_ids ||= account.inboxes.filter(&:active_bot?).map(&:id)
  end

  def bot_conversations
    @bot_conversations ||= account.conversations.where(inbox_id: bot_activated_inbox_ids).where(created_at: range)
  end

  def bot_messages
    # Count outbound messages sent by automation/bots.
    # We support both the built-in bot marker and external providers (e.g. chatbotlevan)
    # that set content_attributes on outgoing messages.
    @bot_messages ||= account.messages.outgoing
                             .where(created_at: range)
                             .where(private: false)
                             .where(
                               "COALESCE(content_attributes ->> 'bot_provider', '') = :provider " \
                               "OR COALESCE(content_attributes ->> 'is_bot_generated', '') IN ('true', 't', '1')",
                               provider: 'chatbotlevan'
                             )
  end

  def debug?
    ActiveModel::Type::Boolean.new.cast(params[:debug])
  end

  def env_debug?
    ActiveModel::Type::Boolean.new.cast(ENV['CHATWOOT_BOT_METRICS_DEBUG'])
  end

  def log_debug(debug)
    totals = debug[:totals] || {}
    Rails.logger.info(
      "[BotMetricsDebug] account_id=#{account.id} since=#{debug[:since]} until=#{debug[:until]} " \
      "outgoing_in_range=#{totals[:outgoing_in_range]} outgoing_public_in_range=#{totals[:outgoing_public_in_range]} " \
      "provider_chatbotlevan=#{totals[:outgoing_public_bot_provider_chatbotlevan]} is_bot_generated_truthy=#{totals[:outgoing_public_is_bot_generated_truthy]} " \
      "combined_match=#{totals[:outgoing_public_combined_match]}"
    )

    sample = debug[:sample_outgoing_public_messages]
    return unless sample.is_a?(Array) && sample.any?

    sample.each do |m|
      ca = m[:content_attributes].is_a?(Hash) ? m[:content_attributes] : {}
      Rails.logger.info(
        "[BotMetricsDebug] sample_message id=#{m[:id]} conversation_id=#{m[:conversation_id]} inbox_id=#{m[:inbox_id]} private=#{m[:private]} " \
        "bot_provider=#{ca['bot_provider'] || ca[:bot_provider]} is_bot_generated=#{ca['is_bot_generated'] || ca[:is_bot_generated]}"
      )
    end
  end

  def debug_payload
    base_scope = account.messages.outgoing.where(created_at: range)
    public_scope = base_scope.where(private: false)

    provider_scope = public_scope.where("COALESCE(content_attributes ->> 'bot_provider', '') = :provider", provider: 'chatbotlevan')
    generated_scope = public_scope.where("COALESCE(content_attributes ->> 'is_bot_generated', '') IN ('true', 't', '1')")
    combined_scope = public_scope.where(
      "COALESCE(content_attributes ->> 'bot_provider', '') = :provider " \
      "OR COALESCE(content_attributes ->> 'is_bot_generated', '') IN ('true', 't', '1')",
      provider: 'chatbotlevan'
    )

    sample = public_scope.order(id: :desc).limit(5).select(:id, :inbox_id, :conversation_id, :private, :created_at, :content_attributes).map do |m|
      {
        id: m.id,
        conversation_id: m.conversation_id,
        inbox_id: m.inbox_id,
        private: m.private,
        created_at: m.created_at,
        content_attributes: m.content_attributes
      }
    end

    {
      since: params[:since],
      until: params[:until],
      totals: {
        outgoing_in_range: base_scope.count,
        outgoing_public_in_range: public_scope.count,
        outgoing_private_in_range: base_scope.where(private: true).count,
        outgoing_public_bot_provider_chatbotlevan: provider_scope.count,
        outgoing_public_is_bot_generated_truthy: generated_scope.count,
        outgoing_public_combined_match: combined_scope.count
      },
      sample_outgoing_public_messages: sample
    }
  end

  def bot_resolutions_count
    account.reporting_events.joins(:conversation).select(:conversation_id).where(account_id: account.id, name: :conversation_bot_resolved,
                                                                                 created_at: range).distinct.count
  end

  def bot_handoffs_count
    account.reporting_events.joins(:conversation).select(:conversation_id).where(account_id: account.id, name: :conversation_bot_handoff,
                                                                                 created_at: range).distinct.count
  end

  def bot_resolution_rate
    return 0 if bot_conversations.count.zero?

    bot_resolutions_count.to_f / bot_conversations.count * 100
  end

  def bot_handoff_rate
    return 0 if bot_conversations.count.zero?

    bot_handoffs_count.to_f / bot_conversations.count * 100
  end
end
