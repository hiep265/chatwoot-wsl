# frozen_string_literal: true

class AiControl::ChatwootReplyReplayService
  REPLAY_AFTER_MINUTES = 60
  ACTIVE_WINDOW_HOURS = 24
  STATE_TTL = 48.hours.to_i
  EXCLUDED_REPLAY_LABELS = %w[ai_handoff ai_paused].freeze

  class << self
    def load_config(account_id)
      stored = parse_json(::Redis::Alfred.get(config_redis_key(account_id)))
      default_config.merge(stored)
    end

    def save_config(account_id, enabled:)
      config = default_config.merge(
        'enabled' => ActiveModel::Type::Boolean.new.cast(enabled),
        'updated_at' => Time.current.iso8601
      )
      ::Redis::Alfred.set(config_redis_key(account_id), config.to_json)
      config
    end

    def default_config
      {
        'enabled' => false,
        'replay_after_minutes' => REPLAY_AFTER_MINUTES,
        'active_window_hours' => ACTIVE_WINDOW_HOURS
      }
    end

    def config_redis_key(account_id)
      "ai_control:chatwoot_reply_replay:config:#{account_id}"
    end

    def state_redis_key(account_id, conversation_id)
      "ai_control:chatwoot_reply_replay:last_attempt:#{account_id}:#{conversation_id}"
    end

    private

    def parse_json(value)
      raw = value.to_s.strip
      return {} if raw.blank?

      parsed = JSON.parse(raw)
      parsed.is_a?(Hash) ? parsed : {}
    rescue JSON::ParserError
      {}
    end
  end

  def perform
    dispatched_count = 0

    Account.find_each do |account|
      config = self.class.load_config(account.id)
      next unless ActiveModel::Type::Boolean.new.cast(config['enabled'])

      due_conversations_for(account, config).find_each do |conversation|
        dispatched_count += replay_conversation(conversation, config)
      end
    end

    dispatched_count
  end

  private

  def due_conversations_for(account, config)
    replay_after_minutes = configured_integer(config, 'replay_after_minutes', REPLAY_AFTER_MINUTES)
    active_window_hours = configured_integer(config, 'active_window_hours', ACTIVE_WINDOW_HOURS)

    account.conversations
           .where(status: %i[open pending])
           .where.not(waiting_since: nil)
           .where(last_activity_at: active_window_hours.hours.ago..replay_after_minutes.minutes.ago)
           .where.not(id: excluded_replay_conversation_ids_for(account))
  end

  def excluded_replay_conversation_ids_for(account)
    account.conversations.tagged_with(EXCLUDED_REPLAY_LABELS, any: true).distinct.pluck(:id)
  end

  def replay_conversation(conversation, config)
    message = latest_waiting_message(conversation)
    return 0 if message.blank?

    replay_after_minutes = configured_integer(config, 'replay_after_minutes', REPLAY_AFTER_MINUTES)
    active_window_hours = configured_integer(config, 'active_window_hours', ACTIVE_WINDOW_HOURS)
    return 0 unless message_in_replay_window?(message, replay_after_minutes, active_window_hours)
    return 0 unless replay_due?(conversation, message, replay_after_minutes)

    webhook_url = chatbotlevan_message_webhook_url
    return 0 if webhook_url.blank?

    WebhookJob.perform_later(
      webhook_url,
      message.webhook_data.merge(event: 'message_created')
    )
    persist_state(conversation, message)
    1
  end

  def latest_waiting_message(conversation)
    scope = conversation.messages.chat
    scope = scope.where('created_at >= ?', conversation.waiting_since) if conversation.waiting_since.present?

    message = scope.reorder(created_at: :asc).last
    return if message.blank? || !message.incoming?

    message
  end

  def message_in_replay_window?(message, replay_after_minutes, active_window_hours)
    message.created_at >= active_window_hours.hours.ago &&
      message.created_at <= replay_after_minutes.minutes.ago
  end

  def replay_due?(conversation, message, replay_after_minutes)
    state = replay_state_for(conversation)
    return true if state.blank?
    return true if state['message_id'].to_s != message.id.to_s

    attempted_at = parse_time(state['attempted_at'])
    return true if attempted_at.blank?

    attempted_at <= replay_after_minutes.minutes.ago
  end

  def replay_state_for(conversation)
    raw = ::Redis::Alfred.get(
      self.class.state_redis_key(conversation.account_id, conversation.display_id)
    ).to_s.strip
    return {} if raw.blank?

    parsed = JSON.parse(raw)
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def persist_state(conversation, message)
    payload = {
      message_id: message.id,
      conversation_id: conversation.display_id,
      attempted_at: Time.current.iso8601
    }
    ::Redis::Alfred.set(
      self.class.state_redis_key(conversation.account_id, conversation.display_id),
      payload.to_json,
      ex: STATE_TTL
    )
  end

  def parse_time(value)
    raw = value.to_s.strip
    return nil if raw.blank?

    Time.zone.parse(raw)
  rescue ArgumentError, TypeError
    nil
  end

  def configured_integer(config, key, default_value)
    Integer(config[key] || default_value)
  rescue ArgumentError, TypeError
    default_value
  end

  def chatbotlevan_message_webhook_url
    base_url = ChatbotlevanEndpointResolver.chatbotlevan_base_url
    return '' if base_url.blank?

    "#{base_url}/webhooks/chatwoot/messages"
  end
end
