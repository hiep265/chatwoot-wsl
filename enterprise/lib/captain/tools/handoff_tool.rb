class Captain::Tools::HandoffTool < Captain::Tools::BasePublicTool
  description 'Hand off the conversation to a human agent when unable to assist further'
  param :reason, type: 'string', desc: 'The reason why handoff is needed (optional)', required: false
  param :is_lead, type: 'string', desc: 'Whether this customer is a potential lead (true/false) (optional)', required: false
  param :customer_request, type: 'string', desc: 'What the customer is requesting (optional)', required: false
  param :is_urgent, type: 'string', desc: 'Whether this is urgent and should be handled immediately (true/false) (optional)', required: false
  param :is_upset, type: 'string', desc: 'Whether the customer seems upset (true/false) (optional)', required: false
  param :pause_bot, type: 'string', desc: 'Pause bot/webhook handling for this conversation (true/false) (optional)', required: false

  def perform(tool_context, reason: nil, is_lead: nil, customer_request: nil, is_urgent: nil, is_upset: nil, pause_bot: nil)
    conversation = find_conversation(tool_context.state)
    return 'Conversation not found' unless conversation

    note = reason.to_s.strip.presence || 'Agent requested handoff'
    reason_text = reason.to_s.strip

    apply_handoff_metadata(
      conversation,
      note: note,
      is_lead: is_lead,
      customer_request: customer_request,
      is_urgent: is_urgent,
      is_upset: is_upset,
      pause_bot: pause_bot
    )

    # Log the handoff with reason
    log_tool_usage('tool_handoff', {
                     conversation_id: conversation.id,
                     reason: note
                   })

    # Use existing handoff mechanism from ResponseBuilderJob
    trigger_handoff(conversation, note)

    "Conversation handed off to human support team#{" (Reason: #{reason_text})" if reason_text.present?}"
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    'Failed to handoff conversation'
  end

  private

  def trigger_handoff(conversation, note)
    # post the reason as a private note
    conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      sender: @assistant,
      account: conversation.account,
      inbox: conversation.inbox,
      content: note
    )

    # Trigger the bot handoff (sets status to open + dispatches events)
    conversation.bot_handoff!

    # Send out of office message if applicable (since template messages were suppressed while Captain was handling)
    send_out_of_office_message_if_applicable(conversation)
  end

  def send_out_of_office_message_if_applicable(conversation)
    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(conversation)
  end

  def apply_handoff_metadata(conversation, note:, is_lead:, customer_request:, is_urgent:, is_upset:, pause_bot:)
    lead = normalize_bool(is_lead)
    urgent = normalize_bool(is_urgent)
    upset = normalize_bool(is_upset)
    paused = normalize_bool(pause_bot)

    custom_attrs = (conversation.custom_attributes || {}).deep_dup
    captain_attrs = (custom_attrs['captain'] || {}).deep_dup
    handoff_attrs = (captain_attrs['handoff'] || {}).deep_dup

    now = Time.zone.now

    handoff_attrs['reason'] = note
    handoff_attrs['customer_request'] = customer_request.to_s.strip.presence if customer_request.present?
    handoff_attrs['is_lead'] = lead unless lead.nil?
    handoff_attrs['is_urgent'] = urgent unless urgent.nil?
    handoff_attrs['is_upset'] = upset unless upset.nil?
    handoff_attrs['pause_bot'] = paused unless paused.nil?
    handoff_attrs['assistant_id'] = @assistant.id
    handoff_attrs['updated_at'] = now.iso8601

    captain_attrs['handoff'] = handoff_attrs
    custom_attrs['captain'] = captain_attrs

    updates = { custom_attributes: custom_attrs }
    updates[:priority] = :urgent if urgent == true
    conversation.update!(updates)

    ensure_labels(conversation, lead: lead, urgent: urgent, upset: upset, paused: paused)
  end

  def ensure_labels(conversation, lead:, urgent:, upset:, paused:)
    labels = ['ai_handoff']
    labels << 'ai_lead' if lead == true
    labels << 'ai_urgent' if urgent == true
    labels << 'ai_upset' if upset == true
    labels << 'ai_paused' if paused == true

    labels = labels.uniq

    labels.each do |label_name|
      label = account_scoped(Label).find_or_create_by!(title: label_name)

      if label_name.in?(%w[ai_lead ai_urgent ai_upset]) && !label.show_on_sidebar?
        label.update!(show_on_sidebar: true)
      end
    end

    conversation.add_labels(labels)
  end

  def normalize_bool(value)
    return nil if value.nil?

    v = value.to_s.strip.downcase
    return true if v.in?(%w[1 true yes y])
    return false if v.in?(%w[0 false no n])

    nil
  end

  # TODO: Future enhancement - Add team assignment capability
  # This tool could be enhanced to:
  # 1. Accept team_id parameter for routing to specific teams
  # 2. Set conversation priority based on handoff reason
  # 3. Add metadata for intelligent agent assignment
  # 4. Support escalation levels (L1 -> L2 -> L3)
  #
  # Example future signature:
  # param :team_id, type: 'string', desc: 'ID of team to assign conversation to', required: false
  # param :priority, type: 'string', desc: 'Priority level (low/medium/high/urgent)', required: false
  # param :escalation_level, type: 'string', desc: 'Support level (L1/L2/L3)', required: false
end
