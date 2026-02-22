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

  private

  def authorize_account_update
    authorize Current.account, :update?
  end

  def chatbotlevan_base_url
    ENV.fetch('CHATBOTLEVAN_BASE_URL', '').to_s.strip.chomp('/')
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

  def parse_json_body(raw_body)
    return {} if raw_body.blank?

    JSON.parse(raw_body)
  rescue JSON::ParserError
    { raw: raw_body.to_s }
  end
end
