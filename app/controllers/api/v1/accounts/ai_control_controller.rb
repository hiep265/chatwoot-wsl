require 'net/http'
require 'uri'
require 'json'

class Api::V1::Accounts::AiControlController < Api::V1::Accounts::BaseController
  BOT_ACCESSIBLE_ACTIONS = %w[manager_daily_raw_messages manager_conversation_messages].freeze

  before_action :authorize_account_update

  def train_faq
    base_url = chatbotlevan_base_url
    unless base_url.present?
      render json: { error: 'CHATBOTLEVAN_BASE_URL is not configured' }, status: :unprocessable_entity
      return
    end

    days = normalize_days(params[:days])
    payload = {
      account_id: Current.account.id.to_s,
      assistant_name: resolved_assistant_name,
      dry_run: ActiveModel::Type::Boolean.new.cast(params[:dry_run]),
      updated_within_seconds: days * 86_400,
      max_conversations: normalize_optional_int(params[:max_conversations]),
      per_conversation_limit: normalize_optional_int(params[:per_conversation_limit]),
      conversations_per_batch: normalize_optional_int(params[:conversations_per_batch])
    }.compact

    response = post_json("#{base_url}/learning/faq/run", payload)
    status = response.code.to_i
    body = parse_json_body(response.body)

    if status.between?(200, 299)
      Rails.logger.info("[AiControl] FAQ Success: #{body.inspect}")
      render json: body, status: :ok
      return
    end

    Rails.logger.error(
      "[AiControl] faq_training_failed account_id=#{Current.account.id} status=#{status} body=#{response.body}"
    )
    render json: { error: 'FAQ training request failed', detail: body }, status: :bad_gateway
  rescue StandardError => e
    Rails.logger.error(
      "[AiControl] faq_training_error account_id=#{Current.account.id} error=#{e.class}:#{e.message}"
    )
    render json: { error: 'Unable to trigger FAQ training', detail: e.message }, status: :bad_gateway
  end

  def payment_review_cases
    base_url = chatbotlevan_base_url
    unless base_url.present?
      render json: { error: 'CHATBOTLEVAN_BASE_URL is not configured' }, status: :unprocessable_entity
      return
    end

    payload = {
      review_status: normalize_review_status(params[:review_status]),
      segment: normalize_segment(params[:segment]),
      limit: normalize_limit(params[:limit]),
      offset: normalize_offset(params[:offset])
    }.compact

    response = get_json("#{base_url}/tools/payment-review-cases", payload)
    status = response.code.to_i
    body = parse_json_body(response.body)

    if status.between?(200, 299)
      render json: enrich_payment_review_cases(body), status: :ok
      return
    end

    Rails.logger.error(
      "[AiControl] payment_review_cases_failed account_id=#{Current.account.id} status=#{status} body=#{response.body}"
    )
    render json: { error: 'Payment review queue request failed', detail: body }, status: :bad_gateway
  rescue StandardError => e
    Rails.logger.error(
      "[AiControl] payment_review_cases_error account_id=#{Current.account.id} error=#{e.class}:#{e.message}"
    )
    render json: { error: 'Unable to fetch payment review queue', detail: e.message }, status: :bad_gateway
  end

  def review_payment_review_case
    base_url = chatbotlevan_base_url
    unless base_url.present?
      render json: { error: 'CHATBOTLEVAN_BASE_URL is not configured' }, status: :unprocessable_entity
      return
    end

    case_id = params[:case_id].to_s.strip
    if case_id.blank?
      render json: { error: 'case_id is required' }, status: :unprocessable_entity
      return
    end

    review_action = normalize_review_action(params[:review_action])
    if review_action.blank?
      render json: { error: 'review_action is invalid' }, status: :unprocessable_entity
      return
    end

    reviewed_by = params[:reviewed_by].to_s.strip
    reviewed_by = Current.user&.email.to_s.strip if reviewed_by.blank?
    reviewed_by = "chatwoot_user_#{Current.user&.id}" if reviewed_by.blank?

    payload = {
      review_action: review_action,
      reviewed_by: reviewed_by,
      review_note: params[:review_note].to_s.strip.presence,
      data: normalize_review_data(params[:data]),
      trigger_post_payment_skill: ActiveModel::Type::Boolean.new.cast(params[:trigger_post_payment_skill])
    }.compact

    if params[:trigger_post_payment_skill].nil?
      payload[:trigger_post_payment_skill] = true
    end

    response = post_json("#{base_url}/tools/payment-review-cases/#{case_id}/review", payload)
    status = response.code.to_i
    body = parse_json_body(response.body)

    if status.between?(200, 299)
      render json: body, status: :ok
      return
    end

    Rails.logger.error(
      "[AiControl] review_payment_case_failed account_id=#{Current.account.id} case_id=#{case_id} status=#{status} body=#{response.body}"
    )
    render json: { error: 'Payment review action request failed', detail: body }, status: :bad_gateway
  rescue StandardError => e
    Rails.logger.error(
      "[AiControl] review_payment_case_error account_id=#{Current.account.id} case_id=#{params[:case_id]} error=#{e.class}:#{e.message}"
    )
    render json: { error: 'Unable to review payment case', detail: e.message }, status: :bad_gateway
  end

  def manager_daily_overview
    proxy_chatbotlevan_manager_get(
      path: '/tools/staff/daily-message-overview',
      payload: {
        account_id: Current.account.id.to_s,
        target_date: normalize_optional_date(params[:target_date]),
        timezone_name: normalize_timezone_name(params[:timezone_name]),
        limit: normalize_limit(params[:limit]),
        max_conversations: normalize_optional_int(params[:max_conversations]),
        max_messages_per_conversation: normalize_optional_int(params[:max_messages_per_conversation])
      },
      failure_message: 'Daily message overview request failed',
      enricher: :enrich_manager_rows
    )
  end

  def manager_daily_raw_messages
    timezone_name = normalize_timezone_name(params[:timezone_name])
    target_date = normalize_optional_date(params[:target_date])
    window = resolve_manager_day_window(
      target_date: target_date,
      timezone_name: timezone_name
    )

    grouped_conversations = {}
    message_total = 0

    Message.includes(:sender, conversation: :contact)
           .where(account_id: Current.account.id)
           .where(created_at: window[:since]...window[:until])
           .order(:created_at, :id)
           .each do |message|
      conversation = message.conversation
      next unless conversation.present?

      conversation_key = conversation.id.to_s
      entry = grouped_conversations[conversation_key] ||= build_manager_raw_conversation_entry(conversation)
      serialized_message = serialize_manager_raw_message(
        message: message,
        conversation: conversation
      )
      entry[:messages] << serialized_message
      entry[:message_count] += 1
      entry[:first_message_at] ||= serialized_message[:created_at]
      entry[:last_message_at] = serialized_message[:created_at]
      message_total += 1
    end

    conversations = grouped_conversations.values.sort_by { |item| item[:last_message_at].to_s }.reverse

    render json: {
      ok: true,
      account_id: Current.account.id.to_s,
      target_date: window[:target_date],
      timezone: window[:timezone_name],
      since: window[:since].utc.iso8601,
      until: window[:until].utc.iso8601,
      message_count: message_total,
      conversation_count: conversations.length,
      conversations: conversations,
      fetched_at: Time.current.utc.iso8601
    }, status: :ok
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error(
      "[AiControl] manager_daily_raw_messages_error account_id=#{Current.account.id} error=#{e.class}:#{e.message}"
    )
    render json: { error: 'Daily raw messages query failed', detail: e.message }, status: :internal_server_error
  end

  def manager_conversation_messages
    conversation_ids = normalize_conversation_ids(params[:conversation_ids])
    if conversation_ids.blank?
      render json: { error: 'conversation_ids is required' }, status: :unprocessable_entity
      return
    end

    limit_per_conversation = normalize_manager_message_limit(
      params[:limit_per_conversation].presence || params[:limit]
    )
    grouped_messages = conversation_ids.each_with_object({}) do |conversation_id, memo|
      memo[conversation_id] = []
    end
    message_total = 0

    Message.includes(:sender, conversation: :contact)
           .where(account_id: Current.account.id, conversation_id: conversation_ids)
           .order(:conversation_id, created_at: :desc, id: :desc)
           .each do |message|
      conversation = message.conversation
      next unless conversation.present?

      conversation_key = conversation.id.to_s
      bucket = grouped_messages[conversation_key]
      next unless bucket
      next if bucket.length >= limit_per_conversation

      bucket << serialize_manager_raw_message(
        message: message,
        conversation: conversation
      )
      message_total += 1
    end

    grouped_messages.each_value(&:reverse!)

    render json: {
      ok: true,
      account_id: Current.account.id.to_s,
      conversation_count: conversation_ids.length,
      limit_per_conversation: limit_per_conversation,
      total_message_count: message_total,
      messages_by_conversation: grouped_messages,
      fetched_at: Time.current.utc.iso8601
    }, status: :ok
  rescue StandardError => e
    Rails.logger.error(
      "[AiControl] manager_conversation_messages_error account_id=#{Current.account.id} error=#{e.class}:#{e.message}"
    )
    render json: { error: 'Conversation messages query failed', detail: e.message }, status: :internal_server_error
  end

  def manager_ai_handoff_queue
    proxy_chatbotlevan_manager_get(
      path: '/tools/staff/ai-handoff-queue',
      payload: {
        account_id: Current.account.id.to_s,
        timezone_name: normalize_timezone_name(params[:timezone_name]),
        limit: normalize_limit(params[:limit]),
        max_conversations: normalize_optional_int(params[:max_conversations])
      },
      failure_message: 'AI handoff queue request failed',
      enricher: :enrich_manager_rows
    )
  end

  def manager_sla_risk_queue
    proxy_chatbotlevan_manager_get(
      path: '/tools/staff/sla-risk-queue',
      payload: {
        account_id: Current.account.id.to_s,
        risk_window_minutes: normalize_optional_int(params[:risk_window_minutes]),
        limit: normalize_limit(params[:limit]),
        max_conversations: normalize_optional_int(params[:max_conversations])
      },
      failure_message: 'SLA risk queue request failed',
      enricher: :enrich_manager_rows
    )
  end

  def manager_follow_up_due_queue
    proxy_chatbotlevan_manager_get(
      path: '/tools/staff/follow-up-due',
      payload: {
        account_id: Current.account.id.to_s,
        stale_after_minutes: normalize_optional_int(params[:stale_after_minutes]),
        limit: normalize_limit(params[:limit]),
        max_conversations: normalize_optional_int(params[:max_conversations])
      },
      failure_message: 'Follow-up due queue request failed',
      enricher: :enrich_manager_rows
    )
  end

  def manager_unassigned_hot_queue
    proxy_chatbotlevan_manager_get(
      path: '/tools/staff/unassigned-hot-queue',
      payload: {
        account_id: Current.account.id.to_s,
        min_waiting_minutes: normalize_optional_int(params[:min_waiting_minutes]),
        limit: normalize_limit(params[:limit]),
        max_conversations: normalize_optional_int(params[:max_conversations])
      },
      failure_message: 'Unassigned hot queue request failed',
      enricher: :enrich_manager_rows
    )
  end

  def manager_customer_360
    conversation_id = params[:conversation_id].to_s.strip
    if conversation_id.blank?
      render json: { error: 'conversation_id is required' }, status: :unprocessable_entity
      return
    end

    proxy_chatbotlevan_manager_get(
      path: '/tools/staff/customer-360',
      payload: {
        account_id: Current.account.id.to_s,
        conversation_id: conversation_id,
        contact_id: params[:contact_id].to_s.strip.presence,
        recent_message_limit: normalize_optional_int(params[:recent_message_limit]),
        memory_limit: normalize_optional_int(params[:memory_limit]),
        memory_query: params[:memory_query].to_s.strip.presence
      },
      failure_message: 'Customer 360 request failed',
      enricher: :enrich_manager_customer_360
    )
  end

  def manager_reply_gap_watch
    proxy_chatbotlevan_manager_get(
      path: '/tools/staff/reply-gap-watch',
      payload: {
        account_id: Current.account.id.to_s,
        min_gap_minutes: normalize_optional_int(params[:min_gap_minutes]),
        limit: normalize_limit(params[:limit]),
        max_conversations: normalize_optional_int(params[:max_conversations])
      },
      failure_message: 'Reply gap watch request failed',
      enricher: :enrich_manager_rows
    )
  end

  def manager_priority_digest
    proxy_chatbotlevan_manager_get(
      path: '/tools/staff/priority-digest',
      payload: {
        account_id: Current.account.id.to_s,
        limit: normalize_optional_int(params[:limit]),
        max_conversations: normalize_optional_int(params[:max_conversations]),
        risk_window_minutes: normalize_optional_int(params[:risk_window_minutes]),
        min_waiting_minutes: normalize_optional_int(params[:min_waiting_minutes]),
        stale_after_minutes: normalize_optional_int(params[:stale_after_minutes]),
        min_gap_minutes: normalize_optional_int(params[:min_gap_minutes])
      },
      failure_message: 'Priority digest request failed',
      enricher: :enrich_manager_rows
    )
  end

  # ── Blocked Inbox Management (AI webhook control) ──

  def blocked_inboxes
    key = blocked_inboxes_redis_key
    blocked_json = ::Redis::Alfred.get(key)
    blocked_ids = blocked_json.present? ? (JSON.parse(blocked_json) rescue []) : []

    render json: { blocked_inbox_ids: blocked_ids }, status: :ok
  end

  def block_inbox
    inbox_id = params[:inbox_id].to_s.strip
    if inbox_id.blank?
      render json: { error: 'inbox_id is required' }, status: :unprocessable_entity
      return
    end

    key = blocked_inboxes_redis_key
    blocked_json = ::Redis::Alfred.get(key)
    blocked_ids = blocked_json.present? ? (JSON.parse(blocked_json) rescue []) : []
    blocked_ids = (blocked_ids + [inbox_id]).uniq

    ::Redis::Alfred.set(key, blocked_ids.to_json)

    Rails.logger.info("[AiControl] block_inbox account_id=#{Current.account.id} inbox_id=#{inbox_id}")
    render json: { blocked_inbox_ids: blocked_ids }, status: :ok
  end

  def unblock_inbox
    inbox_id = params[:inbox_id].to_s.strip
    if inbox_id.blank?
      render json: { error: 'inbox_id is required' }, status: :unprocessable_entity
      return
    end

    key = blocked_inboxes_redis_key
    blocked_json = ::Redis::Alfred.get(key)
    blocked_ids = blocked_json.present? ? (JSON.parse(blocked_json) rescue []) : []
    blocked_ids.delete(inbox_id)

    if blocked_ids.empty?
      ::Redis::Alfred.delete(key)
    else
      ::Redis::Alfred.set(key, blocked_ids.to_json)
    end

    Rails.logger.info("[AiControl] unblock_inbox account_id=#{Current.account.id} inbox_id=#{inbox_id}")
    render json: { blocked_inbox_ids: blocked_ids }, status: :ok
  end

  def toggle_all_inboxes
    action = params[:action_type].to_s.strip.downcase
    inbox_ids = params[:inbox_ids]
    inbox_ids = inbox_ids.map(&:to_s).uniq if inbox_ids.is_a?(Array)

    unless %w[block unblock].include?(action)
      render json: { error: 'action_type must be "block" or "unblock"' }, status: :unprocessable_entity
      return
    end

    key = blocked_inboxes_redis_key

    if action == 'block' && inbox_ids.present?
      blocked_json = ::Redis::Alfred.get(key)
      blocked_ids = blocked_json.present? ? (JSON.parse(blocked_json) rescue []) : []
      blocked_ids = (blocked_ids + inbox_ids).uniq
      ::Redis::Alfred.set(key, blocked_ids.to_json)
    elsif action == 'unblock'
      ::Redis::Alfred.delete(key)
      blocked_ids = []
    else
      blocked_json = ::Redis::Alfred.get(key)
      blocked_ids = blocked_json.present? ? (JSON.parse(blocked_json) rescue []) : []
    end

    Rails.logger.info("[AiControl] toggle_all_inboxes account_id=#{Current.account.id} action=#{action} count=#{blocked_ids.length}")
    render json: { blocked_inbox_ids: blocked_ids }, status: :ok
  end

  def comment_webhook_config
    render json: { comment_webhook_url: chatbotlevan_comment_webhook_url }, status: :ok
  end

  def update_comment_webhook_config
    requested_url = params[:comment_webhook_url].to_s.strip
    if requested_url.blank?
      ::Redis::Alfred.delete(comment_webhook_url_redis_key)
      render json: { status: 'cleared', comment_webhook_url: chatbotlevan_comment_webhook_url }, status: :ok
      return
    end

    begin
      parsed = URI.parse(requested_url)
      unless parsed.is_a?(URI::HTTP) && parsed.host.present?
        render json: { error: 'comment_webhook_url must be a valid http/https URL' }, status: :unprocessable_entity
        return
      end
    rescue URI::InvalidURIError
      render json: { error: 'comment_webhook_url must be a valid URL' }, status: :unprocessable_entity
      return
    end

    normalized_url = requested_url.chomp('/')
    ::Redis::Alfred.set(comment_webhook_url_redis_key, normalized_url)
    render json: { status: 'saved', comment_webhook_url: normalized_url }, status: :ok
  end

  # ── Comment Tab ──

  def comments
    limit = normalize_limit(params[:limit])
    offset = normalize_offset(params[:offset])
    platform = params[:platform].to_s.strip.presence
    status_filter = params[:status].to_s.strip.presence
    inbox_id = params[:inbox_id].to_s.strip.presence

    base_scope = SocialComment.where(account_id: Current.account.id)
    base_scope = base_scope.where(platform: platform) if platform.present?
    base_scope = base_scope.where(inbox_id: inbox_id) if inbox_id.present?
    base_scope = base_scope.where(status: status_filter) if status_filter.present? && SocialComment.statuses.key?(status_filter)

    # Group by post_id to show per-post comment threads
    post_ids = base_scope.select(:post_id).distinct.limit(limit).offset(offset).pluck(:post_id)
    total_posts = base_scope.select(:post_id).distinct.count

    result = post_ids.map do |post_id|
      post_comments = base_scope.where(post_id: post_id).order(created_at: :asc)
      first_comment = post_comments.first

      {
        post_id: post_id,
        platform: first_comment&.platform,
        post_caption: first_comment&.post_caption,
        post_media_url: first_comment&.post_media_url,
        post_permalink: first_comment&.post_permalink,
        post_like_count: first_comment&.post_like_count,
        post_comment_count: first_comment&.post_comment_count,
        inbox_id: first_comment&.inbox_id,
        messages: post_comments.map do |c|
          {
            id: c.id,
            comment_id: c.comment_id,
            parent_comment_id: c.parent_comment_id,
            content: c.content,
            author_name: c.author_name,
            author_id: c.author_id,
            direction: c.direction,
            status: c.status,
            source_reply_id: c.source_reply_id,
            created_at: c.created_at
          }
        end,
        messages_count: post_comments.size,
        last_activity_at: post_comments.last&.created_at
      }
    end

    render json: { comments: result, total: total_posts, limit: limit, offset: offset }, status: :ok
  rescue StandardError => e
    Rails.logger.error("[AiControl] comments_error account_id=#{Current.account.id} error=#{e.class}:#{e.message}")
    render json: { error: 'Unable to fetch comments', detail: e.message }, status: :internal_server_error
  end

  def comment_thread
    post_id = params[:conversation_id] # reusing route param for post_id
    comments = SocialComment.where(account_id: Current.account.id, post_id: post_id)
                            .order(created_at: :asc)

    if comments.empty?
      render json: { error: 'No comments found for this post' }, status: :not_found
      return
    end

    first = comments.first
    render json: {
      post_id: post_id,
      platform: first.platform,
      post_caption: first.post_caption,
      post_media_url: first.post_media_url,
      post_permalink: first.post_permalink,
      messages: comments.map do |c|
        {
          id: c.id,
          comment_id: c.comment_id,
          parent_comment_id: c.parent_comment_id,
          content: c.content,
          author_name: c.author_name,
          author_id: c.author_id,
          direction: c.direction,
          status: c.status,
          source_reply_id: c.source_reply_id,
          created_at: c.created_at
        }
      end
    }, status: :ok
  rescue StandardError => e
    Rails.logger.error("[AiControl] comment_thread_error account_id=#{Current.account.id} error=#{e.class}:#{e.message}")
    render json: { error: 'Unable to fetch comment thread', detail: e.message }, status: :internal_server_error
  end

  def reply_comment
    social_comment = SocialComment.find_by(id: params[:conversation_id], account_id: Current.account.id)
    unless social_comment
      render json: { error: 'Comment not found' }, status: :not_found
      return
    end

    content = params[:message].to_s.strip
    if content.blank?
      render json: { error: 'message is required' }, status: :unprocessable_entity
      return
    end

    # Find the channel for this inbox
    inbox = social_comment.inbox
    channel = inbox&.channel
    unless channel
      render json: { error: 'Channel not found' }, status: :unprocessable_entity
      return
    end

    ::Instagram::SendCommentReplyService.new(
      social_comment: social_comment,
      reply_text: content,
      channel: channel
    ).perform

    Rails.logger.info("[AiControl] reply_comment social_comment_id=#{social_comment.id}")
    render json: { status: 'sent', social_comment_id: social_comment.id }, status: :ok
  rescue StandardError => e
    Rails.logger.error("[AiControl] reply_comment_error account_id=#{Current.account.id} error=#{e.class}:#{e.message}")
    render json: { error: 'Unable to reply comment', detail: e.message }, status: :internal_server_error
  end

  def auto_reply_comment
    social_comment = SocialComment.find_by(id: params[:conversation_id], account_id: Current.account.id)
    unless social_comment
      render json: { error: 'Comment not found' }, status: :not_found
      return
    end

    requested_comment_webhook_url = params[:comment_webhook_url].to_s.strip.chomp('/')
    comment_webhook_url = requested_comment_webhook_url.presence || chatbotlevan_comment_webhook_url
    unless comment_webhook_url.present?
      render json: { error: 'CHATBOTLEVAN comment webhook is not configured' }, status: :unprocessable_entity
      return
    end

    # Trigger chatbotlevan by sending a webhook with the comment data
    payload = {
      event: 'social_comment_created',
      social_comment: {
        id: social_comment.id,
        comment_id: social_comment.comment_id,
        content: social_comment.content,
        author_name: social_comment.author_name,
        post_id: social_comment.post_id,
        post_caption: social_comment.post_caption,
        platform: social_comment.platform,
        inbox_id: social_comment.inbox_id,
        account_id: social_comment.account_id
      }
    }

    WebhookJob.perform_later(comment_webhook_url, payload)

    Rails.logger.info(
      "[AiControl] auto_reply_comment social_comment_id=#{social_comment.id} webhook_url=#{comment_webhook_url}"
    )
    render json: {
      status: 'triggered',
      social_comment_id: social_comment.id,
      webhook_url: comment_webhook_url
    }, status: :ok
  rescue StandardError => e
    Rails.logger.error("[AiControl] auto_reply_comment_error account_id=#{Current.account.id} error=#{e.class}:#{e.message}")
    render json: { error: 'Unable to trigger auto-reply', detail: e.message }, status: :internal_server_error
  end

  private

  def authorize_account_update
    return if Current.user.is_a?(AgentBot) && BOT_ACCESSIBLE_ACTIONS.include?(action_name)

    authorize Current.account, :update?
  end

  def chatbotlevan_base_url
    ENV.fetch('CHATBOTLEVAN_BASE_URL', '').to_s.strip.chomp('/')
  end

  def chatbotlevan_comment_webhook_url
    configured_by_account = ::Redis::Alfred.get(comment_webhook_url_redis_key).to_s.strip
    return configured_by_account.chomp('/') if configured_by_account.present?

    configured_url = ENV.fetch('CHATBOTLEVAN_COMMENT_WEBHOOK_URL', '').to_s.strip
    return configured_url.chomp('/') if configured_url.present?

    base_url = chatbotlevan_base_url
    return '' if base_url.blank?

    "#{base_url}/webhooks/chatwoot/comments"
  end

  def comment_webhook_url_redis_key
    "ai_control:comment_webhook_url:#{Current.account.id}"
  end

  def blocked_inboxes_redis_key
    "ai_control:blocked_inboxes:#{Current.account.id}"
  end

  def resolved_assistant_name
    requested = params[:assistant_name].to_s.strip
    return requested if requested.present?

    ENV.fetch('CHATWOOT_CAPTAIN_ASSISTANT_NAME', '').to_s.strip
  end

  def normalize_days(value)
    parsed = value.to_i
    parsed = 7 if parsed <= 0
    [parsed, 365].min
  end

  def normalize_optional_int(value)
    return nil if value.nil?

    parsed = value.to_i
    return nil if parsed <= 0

    parsed
  end

  def normalize_optional_date(value)
    raw = value.to_s.strip
    return nil if raw.blank?
    return raw if raw.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    nil
  end

  def normalize_timezone_name(value)
    raw = value.to_s.strip
    raw.present? ? raw : 'Asia/Bangkok'
  end

  def resolve_manager_day_window(target_date:, timezone_name:)
    zone = ActiveSupport::TimeZone[timezone_name] || ActiveSupport::TimeZone['Bangkok'] || Time.zone
    resolved_date = target_date.present? ? Date.iso8601(target_date) : zone.today
    since_local = zone.local(resolved_date.year, resolved_date.month, resolved_date.day, 0, 0, 0)
    until_local = since_local + 1.day

    {
      target_date: resolved_date.iso8601,
      timezone_name: zone.tzinfo.name,
      since: since_local.utc,
      until: until_local.utc
    }
  end

  def normalize_review_status(value)
    requested = value.to_s.strip
    return 'payment_review_pending' if requested.blank?
    return nil if requested == 'all'

    allowed = %w[
      payment_review_pending
      payment_review_rejected
      payment_verified_manual
      payment_verified_auto
    ]
    return requested if allowed.include?(requested)

    'payment_review_pending'
  end

  def normalize_review_action(value)
    requested = value.to_s.strip.downcase
    allowed = %w[confirm reject request_more]
    return requested if allowed.include?(requested)

    nil
  end

  def normalize_review_data(value)
    return {} if value.blank?

    if value.respond_to?(:to_unsafe_h)
      return value.to_unsafe_h
    end
    return value if value.is_a?(Hash)

    {}
  end

  def normalize_segment(value)
    requested = value.to_s.strip.downcase
    return nil if requested.blank?

    allowed = %w[online_course offline_course pmu_tool]
    return requested if allowed.include?(requested)

    nil
  end

  def normalize_limit(value)
    parsed = value.to_i
    parsed = 50 if parsed <= 0
    [parsed, 200].min
  end

  def normalize_manager_message_limit(value)
    parsed = value.to_i
    parsed = 120 if parsed <= 0
    [parsed, 200].min
  end

  def normalize_conversation_ids(value)
    raw_values =
      case value
      when Array
        value
      when String
        value.split(',')
      else
        []
      end

    raw_values.filter_map do |item|
      raw_id = item.to_s.strip
      next if raw_id.blank?
      next unless raw_id.match?(/\A\d+\z/)

      raw_id
    end.uniq.first(500)
  end

  def normalize_offset(value)
    parsed = value.to_i
    return 0 if parsed.negative?

    [parsed, 100_000].min
  end

  def proxy_chatbotlevan_manager_get(path:, payload:, failure_message:, enricher: nil)
    base_url = chatbotlevan_base_url
    unless base_url.present?
      render json: { error: 'CHATBOTLEVAN_BASE_URL is not configured' }, status: :unprocessable_entity
      return
    end

    response = get_json("#{base_url}#{path}", payload.compact)
    status = response.code.to_i
    body = parse_json_body(response.body)

    if status.between?(200, 299)
      body = send(enricher, body) if enricher.present?
      render json: body, status: :ok
      return
    end

    Rails.logger.error(
      "[AiControl] manager_proxy_failed account_id=#{Current.account.id} path=#{path} status=#{status} body=#{response.body}"
    )
    render json: { error: failure_message, detail: body }, status: :bad_gateway
  rescue StandardError => e
    Rails.logger.error(
      "[AiControl] manager_proxy_error account_id=#{Current.account.id} path=#{path} error=#{e.class}:#{e.message}"
    )
    render json: { error: failure_message.sub('request failed', 'unavailable'), detail: e.message }, status: :bad_gateway
  end

  def post_json(url, payload)
    uri = URI.parse(url)
    request = Net::HTTP::Post.new(uri.request_uri)
    request['Content-Type'] = 'application/json'

    token = ENV.fetch('CHATBOTLEVAN_API_TOKEN', '').to_s.strip
    request['Authorization'] = "Bearer #{token}" if token.present?
    request.body = payload.to_json

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 10
    http.read_timeout = 600
    http.request(request)
  end

  def get_json(url, query = {})
    uri = URI.parse(url)
    uri.query = URI.encode_www_form(query.compact) if query.present?

    request = Net::HTTP::Get.new(uri.request_uri)
    request['Content-Type'] = 'application/json'

    token = ENV.fetch('CHATBOTLEVAN_API_TOKEN', '').to_s.strip
    request['Authorization'] = "Bearer #{token}" if token.present?

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'
    http.open_timeout = 10
    http.read_timeout = 60
    http.request(request)
  end

  def parse_json_body(raw_body)
    return {} if raw_body.blank?

    JSON.parse(raw_body)
  rescue JSON::ParserError
    { raw: raw_body.to_s }
  end

  def build_manager_raw_conversation_entry(conversation)
    {
      conversation_id: conversation.id.to_s,
      conversation_display_id: conversation.display_id,
      contact_id: conversation.contact_id.to_s,
      contact_name: resolve_contact_name(conversation.contact, conversation.contact_id),
      status: conversation.status,
      priority: conversation.priority,
      inbox_id: conversation.inbox_id.to_s,
      assignee_id: conversation.assignee_id&.to_s,
      waiting_since: conversation.waiting_since&.utc&.iso8601,
      labels: conversation.cached_label_list_array,
      message_count: 0,
      first_message_at: nil,
      last_message_at: nil,
      messages: []
    }
  end

  def serialize_manager_raw_message(message:, conversation:)
    {
      id: message.id.to_s,
      conversation_id: conversation.id.to_s,
      conversation_display_id: conversation.display_id,
      message_type: message.message_type,
      message_type_code: message.message_type_before_type_cast,
      content_type: message.content_type,
      private: message.private?,
      content: message.content,
      created_at: message.created_at&.utc&.iso8601,
      sender_id: message.sender_id&.to_s,
      sender_type: message.sender_type,
      sender_name: resolve_message_sender_name(message, conversation),
      status: message.status,
      source_id: message.source_id.presence,
      content_attributes: message.content_attributes.presence,
      additional_attributes: message.additional_attributes.presence
    }.compact
  end

  def resolve_message_sender_name(message, conversation)
    return message.sender.name if message.sender.respond_to?(:name) && message.sender.name.present?
    return conversation.contact.name if message.incoming? && conversation.contact&.name.present?
    return Current.user.name if message.outgoing? && Current.user&.name.present?

    nil
  end

  def enrich_payment_review_cases(body)
    return body unless body.is_a?(Hash)

    rows = body['cases']
    return body unless rows.is_a?(Array)

    conversation_ids = rows.filter_map do |row|
      next unless row.is_a?(Hash)

      raw_id = row['conversation_id'].to_s.strip
      next if raw_id.blank? || raw_id !~ /\A\d+\z/

      raw_id
    end.uniq
    return body if conversation_ids.blank?

    conversation_map = Current.account.conversations
                              .includes(:contact)
                              .where(id: conversation_ids)
                              .index_by { |conversation| conversation.id.to_s }

    rows.each do |row|
      next unless row.is_a?(Hash)

      conversation_id = row['conversation_id'].to_s.strip
      conversation = conversation_map[conversation_id]
      next unless conversation

      contact = conversation.contact
      row['conversation_display_id'] ||= conversation.display_id
      row['contact_name'] ||= resolve_contact_name_for_payment_case(row, contact)
      row['contact_avatar_url'] ||= contact&.avatar_url
    end

    body
  end

  def enrich_manager_rows(body)
    return body unless body.is_a?(Hash)

    row_keys = %w[items top_priorities]
    conversation_ids = row_keys.flat_map do |key|
      rows = body[key]
      next [] unless rows.is_a?(Array)

      rows.filter_map do |row|
        next unless row.is_a?(Hash)

        raw_id = row['conversation_id'].to_s.strip
        next if raw_id.blank? || raw_id !~ /\A\d+\z/

        raw_id
      end
    end.uniq
    return body if conversation_ids.blank?

    conversation_map = Current.account.conversations
                              .includes(:contact)
                              .where(id: conversation_ids)
                              .index_by { |conversation| conversation.id.to_s }

    row_keys.each do |key|
      rows = body[key]
      next unless rows.is_a?(Array)

      rows.each do |row|
        next unless row.is_a?(Hash)

        conversation = conversation_map[row['conversation_id'].to_s.strip]
        next unless conversation

        contact = conversation.contact
        row['conversation_display_id'] ||= conversation.display_id
        row['contact_name'] ||= resolve_contact_name(contact, row['contact_id'])
        row['contact_avatar_url'] ||= contact&.avatar_url
        row['inbox_id'] ||= conversation.inbox_id
      end
    end

    body
  end

  def enrich_manager_customer_360(body)
    return body unless body.is_a?(Hash)

    conversation_id = body['conversation_id'].to_s.strip
    return body if conversation_id.blank? || conversation_id !~ /\A\d+\z/

    conversation = Current.account.conversations.includes(:contact).find_by(id: conversation_id)
    return body unless conversation

    body['conversation'] = {} unless body['conversation'].is_a?(Hash)
    body['conversation']['display_id'] ||= conversation.display_id
    body['conversation']['inbox_id'] ||= conversation.inbox_id

    contact = conversation.contact
    body['contact_profile'] = {} unless body['contact_profile'].is_a?(Hash)
    body['contact_profile']['name'] ||= resolve_contact_name(contact, body['contact_id'])
    body['contact_profile']['avatar_url'] ||= contact&.avatar_url
    body['contact_profile']['email'] ||= contact&.email
    body['contact_profile']['phone_number'] ||= contact&.phone_number

    body
  end

  def resolve_contact_name_for_payment_case(row, contact)
    return contact.name if contact&.name.present?
    return contact.phone_number if contact&.phone_number.present?
    return contact.email if contact&.email.present?

    fallback_contact_id = row['contact_id'].to_s.strip
    return "Contact ##{fallback_contact_id}" if fallback_contact_id.present?

    'Khách hàng'
  end

  def resolve_contact_name(contact, fallback_contact_id = nil)
    return contact.name if contact&.name.present?
    return contact.phone_number if contact&.phone_number.present?
    return contact.email if contact&.email.present?

    fallback = fallback_contact_id.to_s.strip
    return "Contact ##{fallback}" if fallback.present?

    'Khách hàng'
  end
end
