class Api::V1::Accounts::Captain::AssistantResponsesController < Api::V1::Accounts::BaseController
  before_action :current_account
  before_action -> { check_authorization(Captain::Assistant) }

  before_action :set_current_page, only: [:index]
  before_action :set_assistant, only: [:create]
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
    limit = 5 if limit <= 0
    limit = 20 if limit > 20

    min_similarity = permitted_params[:min_similarity].to_f
    min_similarity = 0.7 if min_similarity <= 0 || min_similarity > 1
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
    @response = Current.account.captain_assistant_responses.new(response_params)
    @response.documentable = Current.user
    @response.save!
  end

  def update
    @response.update!(response_params)
  end

  def destroy
    @response.destroy
    head :no_content
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

  def set_assistant
    @assistant = Current.account.captain_assistants.find_by(id: params[:assistant_id])
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
    params.permit(:id, :assistant_id, :page, :document_id, :account_id, :status, :search, :query, :limit, :min_similarity)
  end

  def response_params
    params.require(:assistant_response).permit(
      :question,
      :answer,
      :assistant_id,
      :status
    )
  end
end
