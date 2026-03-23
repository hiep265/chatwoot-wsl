require 'json'
require 'net/http'
require 'uri'

class Api::V1::Accounts::Captain::AssistantResponsesController < Api::V1::Accounts::BaseController
  before_action :current_account

  before_action :set_current_page, only: [:index]
  before_action :set_responses, except: [:create]
  before_action :set_response, only: [:show, :update, :destroy]

  RESULTS_PER_PAGE = 25
  def index
    filtered_query = apply_filters(@responses)
    @responses_count = filtered_query.count
    @responses = filtered_query.page(@current_page).per(RESULTS_PER_PAGE)
  end

  def show; end

  def semantic_search
    query = permitted_params[:query].to_s.strip
    limit = permitted_params[:limit].to_i
    limit = Captain::AssistantResponse::DEFAULT_SEARCH_LIMIT if limit <= 0
    limit = Captain::AssistantResponse::MAX_SEARCH_LIMIT if limit > Captain::AssistantResponse::MAX_SEARCH_LIMIT

    min_similarity = permitted_params[:min_similarity].to_f
    min_similarity = Captain::AssistantResponse::DEFAULT_MIN_SIMILARITY if min_similarity <= 0 || min_similarity > 1
    max_distance = 1.0 - min_similarity

    if query.blank?
      @responses = []
      @responses_count = 0
      return
    end

    embedding = Captain::Llm::EmbeddingService.new(account_id: Current.account.id).get_embedding(query)

    base_query = Current.account.captain_assistant_responses
                        .approved
                        .where.not(embedding: nil)
                        .includes(:documentable)

    base_query = base_query.where(assistant_id: permitted_params[:assistant_id]) if permitted_params[:assistant_id].present?

    if permitted_params[:document_id].present?
      base_query = base_query.where(
        documentable_id: permitted_params[:document_id],
        documentable_type: 'Captain::Document'
      )
    end

    candidates_limit = [limit * 5, 100].min
    candidates = base_query.nearest_neighbors(:embedding, embedding, distance: 'cosine').limit(candidates_limit)

    @responses = candidates.select do |response|
      response.respond_to?(:neighbor_distance) && response.neighbor_distance.present? && response.neighbor_distance.to_f <= max_distance
    end.first(limit)
    @responses_count = @responses.size
  rescue StandardError => e
    Rails.logger.error "AssistantResponses semantic_search error: #{e.message}"
    @responses = []
    @responses_count = 0
  end

  def create
    documentable = response_documentable
    assistant_id = resolved_assistant_id(documentable)
    if assistant_id.blank?
      render json: { error: 'Không tìm thấy assistant cho hội thoại này' }, status: :unprocessable_entity
      return
    end

    @response = Current.account.captain_assistant_responses.new(
      response_params.merge(assistant_id: assistant_id)
    )
    @response.documentable = documentable
    @response.save!
  end

  def update
    @response.update!(response_params)
  end

  def destroy
    @response.destroy
    head :no_content
  end

  # Scan answer từ conversation gốc
  def scan_answer
    @response = Current.account.captain_assistant_responses.find(permitted_params[:id])
    base_url = chatbotlevan_base_url
    unless base_url.present?
      render json: { success: false, error: 'CHATBOTLEVAN_BASE_URL is not configured' }, status: :unprocessable_entity
      return
    end

    response = post_chatbotlevan_json(
      "#{base_url}/learning/faq/pending/#{@response.id}/scan",
      { account_id: Current.account.id.to_s }
    )
    status = response.code.to_i
    body = parse_chatbotlevan_json_body(response.body)

    if status.between?(200, 299)
      render json: body, status: :ok
      return
    end

    Rails.logger.error(
      "[Captain Pending] scan_answer_proxy_failed account_id=#{Current.account.id} response_id=#{@response.id} status=#{status} body=#{response.body}"
    )
    render json: {
      success: false,
      error: body['detail'].presence || body['error'].presence || 'Lỗi khi scan answer'
    }, status: :bad_gateway
  rescue StandardError => e
    Rails.logger.error "[Captain Pending] scan_answer_proxy_error response_id=#{@response.id} error=#{e.class}: #{e.message}"
    render json: { success: false, error: e.message }, status: :bad_gateway
  end

  # Scan tất cả pending FAQs
  def scan_all_pending
    base_url = chatbotlevan_base_url
    unless base_url.present?
      render json: { error: 'CHATBOTLEVAN_BASE_URL is not configured' }, status: :unprocessable_entity
      return
    end

    payload = {
      account_id: Current.account.id.to_s,
      assistant_id: params[:assistant_id].presence
    }.compact
    response = post_chatbotlevan_json("#{base_url}/learning/faq/pending/scan", payload)
    status = response.code.to_i
    body = parse_chatbotlevan_json_body(response.body)

    if status.between?(200, 299)
      render json: body, status: :ok
      return
    end

    Rails.logger.error(
      "[Captain Pending] scan_all_proxy_failed account_id=#{Current.account.id} assistant_id=#{params[:assistant_id]} status=#{status} body=#{response.body}"
    )
    render json: {
      error: body['detail'].presence || body['error'].presence || 'Lỗi khi scan all'
    }, status: :bad_gateway
  rescue StandardError => e
    Rails.logger.error "[Captain Pending] scan_all_proxy_error account_id=#{Current.account.id} error=#{e.class}: #{e.message}"
    render json: { error: e.message }, status: :bad_gateway
  end

  private

  def apply_filters(base_query)
    base_query = base_query.where(assistant_id: permitted_params[:assistant_id]) if permitted_params[:assistant_id].present?

    if permitted_params[:document_id].present?
      base_query = base_query.where(
        documentable_id: permitted_params[:document_id],
        documentable_type: 'Captain::Document'
      )
    end

    base_query = base_query.where(status: permitted_params[:status]) if permitted_params[:status].present?

    if permitted_params[:search].present?
      search_term = "%#{permitted_params[:search]}%"
      base_query = base_query.where(
        'question ILIKE :search OR answer ILIKE :search',
        search: search_term
      )
    end

    base_query
  end

  def set_responses
    @responses = Current.account.captain_assistant_responses.includes(:assistant, :documentable).ordered
  end

  def set_response
    @response = @responses.find(permitted_params[:id])
  end

  def set_current_page
    @current_page = permitted_params[:page] || 1
  end

  def permitted_params
    params.permit(
      :id, :assistant_id, :page, :document_id, :conversation_id, :account_id,
      :status, :search, :query, :limit, :min_similarity
    )
  end

  def response_params
    params.require(:assistant_response).permit(
      :question,
      :answer,
      :assistant_id,
      :status
    )
  end

  def response_documentable
    return Current.user if permitted_params[:conversation_id].blank?

    find_conversation(permitted_params[:conversation_id]) || Current.user
  end

  def resolved_assistant_id(documentable)
    return permitted_params[:assistant_id] if permitted_params[:assistant_id].present?
    return unless documentable

    Current.account.captain_assistants.ordered.first&.id
  end

  def find_conversation(conversation_reference)
    return if conversation_reference.blank?

    Current.account.conversations.find_by(id: conversation_reference) ||
      Current.account.conversations.find_by(display_id: conversation_reference)
  end

  def chatbotlevan_base_url
    ChatbotlevanEndpointResolver.chatbotlevan_base_url
  end

  def post_chatbotlevan_json(url, payload)
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

  def parse_chatbotlevan_json_body(raw_body)
    return {} if raw_body.blank?

    JSON.parse(raw_body)
  rescue JSON::ParserError
    { 'raw' => raw_body.to_s }
  end
end
