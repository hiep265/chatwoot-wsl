require 'net/http'
require 'uri'
require 'json'

class Api::V1::Accounts::AiControlController < Api::V1::Accounts::BaseController
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

  # ── Comment Tab ──

  def comments
    limit = normalize_limit(params[:limit])
    offset = normalize_offset(params[:offset])
    platform = params[:platform].to_s.strip.presence
    status_filter = params[:status].to_s.strip.presence
    inbox_id = params[:inbox_id].to_s.strip.presence

    scope = Current.account.conversations
                    .where("additional_attributes->>'type' IN (?)", %w[instagram_comment facebook_comment])
                    .order(last_activity_at: :desc)

    scope = scope.where("additional_attributes->>'platform' = ?", platform) if platform.present?
    scope = scope.where(inbox_id: inbox_id) if inbox_id.present?

    # Status filtering via conversation status
    if status_filter.present?
      case status_filter
      when 'pending'
        scope = scope.where(status: :pending)
      when 'resolved'
        scope = scope.where(status: :resolved)
      when 'open'
        scope = scope.where(status: :open)
      end
    end

    total = scope.count
    conversations = scope.limit(limit).offset(offset).includes(:contact, :inbox, :messages)

    result = conversations.map do |conversation|
      last_message = conversation.messages.order(created_at: :desc).first
      {
        conversation_id: conversation.id,
        display_id: conversation.display_id,
        status: conversation.status,
        platform: conversation.additional_attributes['platform'],
        post_id: conversation.additional_attributes['post_id'],
        post_caption: conversation.additional_attributes['post_caption'],
        post_media_url: conversation.additional_attributes['post_media_url'],
        post_like_count: conversation.additional_attributes['post_like_count'],
        post_comment_count: conversation.additional_attributes['post_comment_count'],
        post_permalink: conversation.additional_attributes['post_permalink'],
        root_comment_id: conversation.additional_attributes['root_comment_id'],
        inbox_id: conversation.inbox_id,
        inbox_name: conversation.inbox&.name,
        contact_name: conversation.contact&.name,
        contact_avatar_url: conversation.contact&.avatar_url,
        last_message_content: last_message&.content,
        last_message_at: last_message&.created_at,
        messages_count: conversation.messages.count,
        created_at: conversation.created_at,
        last_activity_at: conversation.last_activity_at
      }
    end

    render json: { comments: result, total: total, limit: limit, offset: offset }, status: :ok
  rescue StandardError => e
    Rails.logger.error("[AiControl] comments_error account_id=#{Current.account.id} error=#{e.class}:#{e.message}")
    render json: { error: 'Unable to fetch comments', detail: e.message }, status: :internal_server_error
  end

  def comment_thread
    conversation = Current.account.conversations.find_by(id: params[:conversation_id])
    unless conversation
      render json: { error: 'Conversation not found' }, status: :not_found
      return
    end

    messages = conversation.messages.order(created_at: :asc).map do |msg|
      {
        id: msg.id,
        content: msg.content,
        message_type: msg.message_type,
        source_id: msg.source_id,
        sender_name: msg.sender&.name,
        sender_type: msg.sender_type,
        content_attributes: msg.content_attributes,
        created_at: msg.created_at,
        status: msg.status
      }
    end

    render json: {
      conversation_id: conversation.id,
      display_id: conversation.display_id,
      status: conversation.status,
      additional_attributes: conversation.additional_attributes,
      messages: messages
    }, status: :ok
  rescue StandardError => e
    Rails.logger.error("[AiControl] comment_thread_error account_id=#{Current.account.id} error=#{e.class}:#{e.message}")
    render json: { error: 'Unable to fetch comment thread', detail: e.message }, status: :internal_server_error
  end

  def reply_comment
    conversation = Current.account.conversations.find_by(id: params[:conversation_id])
    unless conversation
      render json: { error: 'Conversation not found' }, status: :not_found
      return
    end

    content = params[:message].to_s.strip
    if content.blank?
      render json: { error: 'message is required' }, status: :unprocessable_entity
      return
    end

    message = conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :outgoing,
      content: content,
      sender: Current.user,
      content_attributes: {
        is_social_comment: true,
        is_bot_generated: false
      }
    )

    Rails.logger.info(
      "[AiControl] reply_comment conversation_id=#{conversation.id} message_id=#{message.id}"
    )
    render json: { message_id: message.id, status: 'sent' }, status: :ok
  rescue StandardError => e
    Rails.logger.error("[AiControl] reply_comment_error account_id=#{Current.account.id} error=#{e.class}:#{e.message}")
    render json: { error: 'Unable to reply comment', detail: e.message }, status: :internal_server_error
  end

  def auto_reply_comment
    conversation = Current.account.conversations.find_by(id: params[:conversation_id])
    unless conversation
      render json: { error: 'Conversation not found' }, status: :not_found
      return
    end

    # Trigger chatbotlevan by re-dispatching the last incoming message's webhook event.
    # The WebhookListener will pick it up and forward to chatbotlevan.
    last_incoming = conversation.messages.where(message_type: :incoming).order(created_at: :desc).first
    unless last_incoming
      render json: { error: 'No incoming message to trigger auto-reply' }, status: :unprocessable_entity
      return
    end

    # Fire the webhook event for chatbotlevan to process
    payload = last_incoming.webhook_data.merge(event: 'message_created')
    account = conversation.account

    account.webhooks.account_type.each do |webhook|
      next unless webhook.subscriptions.include?('message_created')

      WebhookJob.perform_later(webhook.url, payload)
    end

    Rails.logger.info(
      "[AiControl] auto_reply_comment conversation_id=#{conversation.id} " \
      "message_id=#{last_incoming.id}"
    )
    render json: { status: 'triggered', message_id: last_incoming.id }, status: :ok
  rescue StandardError => e
    Rails.logger.error("[AiControl] auto_reply_comment_error account_id=#{Current.account.id} error=#{e.class}:#{e.message}")
    render json: { error: 'Unable to trigger auto-reply', detail: e.message }, status: :internal_server_error
  end

  private

  def authorize_account_update
    authorize Current.account, :update?
  end

  def chatbotlevan_base_url
    ENV.fetch('CHATBOTLEVAN_BASE_URL', '').to_s.strip.chomp('/')
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

  def normalize_offset(value)
    parsed = value.to_i
    return 0 if parsed.negative?

    [parsed, 100_000].min
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

  def resolve_contact_name_for_payment_case(row, contact)
    return contact.name if contact&.name.present?
    return contact.phone_number if contact&.phone_number.present?
    return contact.email if contact&.email.present?

    fallback_contact_id = row['contact_id'].to_s.strip
    return "Contact ##{fallback_contact_id}" if fallback_contact_id.present?

    'Khách hàng'
  end
end
