module Enterprise::AgentBotListener
  def conversation_resolved(event)
    conversation = extract_conversation_and_account(event)[0]
    return if bot_paused_for_conversation?(conversation)

    super
  end

  def conversation_opened(event)
    conversation = extract_conversation_and_account(event)[0]
    return if bot_paused_for_conversation?(conversation)

    super
  end

  private

  def process_message_event(method_name, agent_bot, message, event)
    conversation = message.conversation

    if bot_paused_for_conversation?(conversation)
      unpause_if_human_reply!(conversation, message)
      return
    end

    super
  end

  def bot_paused_for_conversation?(conversation)
    return false if conversation.blank?

    paused_label = conversation.label_list.include?('ai_paused')
    paused_attr = conversation.custom_attributes&.dig('captain', 'handoff', 'pause_bot')

    paused_label || paused_attr == true
  end

  def unpause_if_human_reply!(conversation, message)
    return if message.blank?

    is_human_reply = message.outgoing? && message.sender_type == 'User' && !message.private?
    return unless is_human_reply

    custom_attrs = (conversation.custom_attributes || {}).deep_dup
    captain_attrs = (custom_attrs['captain'] || {}).deep_dup
    handoff_attrs = (captain_attrs['handoff'] || {}).deep_dup

    handoff_attrs['pause_bot'] = false
    handoff_attrs['unpaused_at'] = Time.zone.now.iso8601

    captain_attrs['handoff'] = handoff_attrs
    custom_attrs['captain'] = captain_attrs

    conversation.label_list.remove('ai_paused') if conversation.label_list.include?('ai_paused')

    conversation.custom_attributes = custom_attrs
    conversation.save!
  rescue StandardError => e
    Rails.logger.warn("[Enterprise::AgentBotListener] failed_to_unpause conversation_id=#{conversation&.id} error=#{e.class} #{e.message}")
  end
end
