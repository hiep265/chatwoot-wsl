class MessageFinder
  def initialize(conversation, params)
    @conversation = conversation
    @params = params
  end

  def perform
    current_messages
  end

  private

  def conversation_messages
    @conversation.messages.includes(:attachments, :sender, sender: { avatar_attachment: [:blob] })
  end

  def messages
    relation = conversation_messages
    unless @params[:include_session_trace]
      relation = relation.where.not(message_type: Message.message_types[:session_trace])
    end
    return relation if @params[:filter_internal_messages].blank?

    relation.where.not('private = ? OR message_type = ?', true, Message.message_types[:activity])
  end

  def current_messages
    if @params[:after].present? && @params[:before].present?
      messages_between(@params[:after].to_i, @params[:before].to_i)
    elsif @params[:before].present?
      messages_before(@params[:before].to_i)
    elsif @params[:after].present?
      messages_after(@params[:after].to_i)
    else
      messages_latest
    end
  end

  def messages_after(after_id)
    messages.reorder('created_at asc, id asc').where('id > ?', after_id).limit(100)
  end

  def messages_before(before_id)
    if @params[:include_session_trace]
      window_start_id = session_trace_window_start_id(before_id: before_id)
      return messages.reorder('created_at desc, id desc').where('id < ?', before_id).limit(20).reverse if window_start_id.blank?

      return messages.reorder('created_at asc, id asc').where('id >= ? AND id < ?', window_start_id, before_id)
    end

    messages.reorder('created_at desc, id desc').where('id < ?', before_id).limit(20).reverse
  end

  def messages_between(after_id, before_id)
    messages.reorder('created_at asc, id asc').where('id >= ? AND id < ?', after_id, before_id).limit(1000)
  end

  def messages_latest
    if @params[:include_session_trace]
      window_start_id = session_trace_window_start_id
      return messages.reorder('created_at desc, id desc').limit(20).reverse if window_start_id.blank?

      return messages.reorder('created_at asc, id asc').where('id >= ?', window_start_id)
    end

    messages.reorder('created_at desc, id desc').limit(20).reverse
  end

  def session_trace_window_start_id(before_id: nil)
    relation = conversation_messages.where.not(message_type: Message.message_types[:session_trace])
    relation = relation.where('id < ?', before_id) if before_id.present?

    relation.reorder('created_at desc, id desc').limit(20).last&.id
  end
end
