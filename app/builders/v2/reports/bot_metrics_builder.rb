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
    
    # Debug: thêm thông tin chi tiết khi gọi với debug=true
    if debug_enabled?
      payload[:debug] = debug_info
    end
    
    payload
  end

  private

  def debug_enabled?
    params[:debug] == 'true' || params[:debug] == true
  end

  def debug_info
    base_scope = account.messages.outgoing.where(created_at: range)
    base_public = base_scope.where(private: false)
    
    {
      account_id: account.id,
      time_range: { since: params[:since], until: params[:until] },
      outgoing_in_range: base_scope.count,
      outgoing_public_in_range: base_public.count,
      outgoing_public_with_content_attributes: base_public.where.not(content_attributes: [nil, {}]).count,
      outgoing_public_with_bot_provider_key: base_public.where("content_attributes ->> 'bot_provider' IS NOT NULL").count,
      outgoing_public_is_bot_generated_true: base_public.where("content_attributes @> '{\"is_bot_generated\": true}'").count,
      bot_provider_chatbotlevan: base_public.where("COALESCE(content_attributes ->> 'bot_provider', '') = 'chatbotlevan'").count,
      recent_outgoing_public_samples: base_public
        .order(id: :desc)
        .limit(10)
        .select(:id, :conversation_id, :created_at, :private, :sender_type, :content_attributes)
        .map { |m|
          {
            id: m.id,
            conversation_id: m.conversation_id,
            created_at: m.created_at.to_s,
            created_at_unix: m.created_at.to_i,
            sender_type: m.sender_type,
            private: m.private,
            content_attributes: m.content_attributes
          }
        },
      sample_ids_108_111: account.messages.where(id: [108, 109, 110, 111]).select(:id, :conversation_id, :created_at, :content_attributes).map { |m| 
        { 
          id: m.id, 
          conversation_id: m.conversation_id, 
          created_at: m.created_at.to_s, 
          created_at_unix: m.created_at.to_i,
          in_range: range.include?(m.created_at),
          content_attributes: m.content_attributes,
          bot_provider_sql: m[:content_attributes] ? m[:content_attributes]['bot_provider'] : nil
        }
      }
    }
  end

  def bot_activated_inbox_ids
    @bot_activated_inbox_ids ||= account.inboxes.filter(&:active_bot?).map(&:id)
  end

  def bot_conversations
    @bot_conversations ||= account.conversations.where(inbox_id: bot_activated_inbox_ids).where(created_at: range)
  end

  def bot_messages
    # Đếm tin nhắn bot từ chatbotlevan: dùng @> operator (JSON contains) hoạt động với cả JSON và JSONB
    @bot_messages ||= account.messages.outgoing
                             .where(created_at: range)
                             .where(private: false)
                             .where("content_attributes @> '{\"is_bot_generated\": true}' OR content_attributes @> '{\"bot_provider\": \"chatbotlevan\"}'")
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
