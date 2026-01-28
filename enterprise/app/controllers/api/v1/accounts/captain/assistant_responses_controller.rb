class Api::V1::Accounts::Captain::AssistantResponsesController < Api::V1::Accounts::BaseController
  before_action :current_account

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

  # Scan answer từ conversation gốc
  def scan_answer
    @response = Current.account.captain_assistant_responses.find(permitted_params[:id])
    Rails.logger.info("scan_answer response_id=#{@response.id}")
    
    # Parse metadata từ answer placeholder (JSON)
    begin
      metadata = JSON.parse(@response.answer)
    rescue JSON::ParserError
      metadata = {}
    end
    Rails.logger.info("scan_answer metadata=#{metadata}")
    
    conversation_id = metadata['conversation_id'] || @response.documentable_id
    message_id = metadata['message_id']
    Rails.logger.info("scan_answer conversation_id=#{conversation_id} message_id=#{message_id}")
    
    unless conversation_id.present?
      render json: { 
        success: false, 
        error: 'FAQ này không có link đến conversation gốc'
      }, status: :unprocessable_entity
      return
    end

    conversation = Current.account.conversations.find_by(id: conversation_id)
    unless conversation
      render json: { success: false, error: 'Không tìm thấy conversation' }, status: :not_found
      return
    end
    
    question = @response.question
    Rails.logger.info("scan_answer question=#{question}")
    
    # Lấy messages từ message_id xuống 5 tin nhắn
    messages_text = extract_messages_from_position(conversation, message_id, 5)
    Rails.logger.info("scan_answer messages_text_size=#{messages_text.to_s.length}")
    
    # Dùng LLM để extract câu trả lời
    suggested_answer = extract_answer_with_llm(messages_text, question)
    if suggested_answer.to_s.include?('[Không tìm thấy')
      fallback_answer = extract_first_agent_reply(messages_text)
      suggested_answer = fallback_answer if fallback_answer.present?
    end
    Rails.logger.info("scan_answer suggested_answer=#{suggested_answer}")
    
    render json: {
      success: true,
      suggested_answer: suggested_answer,
      conversation_id: conversation.display_id,
      message_id: message_id
    }
  rescue StandardError => e
    Rails.logger.error "scan_answer error: #{e.message}"
    render json: { success: false, error: e.message }, status: :internal_server_error
  end

  # Scan tất cả pending FAQs
  def scan_all_pending
    pending_responses = Current.account.captain_assistant_responses.pending
    pending_responses = pending_responses.where(assistant_id: params[:assistant_id]) if params[:assistant_id].present?
    
    processed = 0
    success_count = 0
    failed_count = 0
    
    pending_responses.find_each do |response|
      begin
        # Parse metadata từ answer placeholder
        metadata = JSON.parse(response.answer) rescue {}
        conversation_id = metadata['conversation_id'] || response.documentable_id
        message_id = metadata['message_id']
        
        next unless conversation_id.present?
        
        conversation = Current.account.conversations.find_by(id: conversation_id)
        next unless conversation
        
        # Lấy messages và extract answer
        messages_text = extract_messages_from_position(conversation, message_id, 5)
        suggested_answer = extract_answer_with_llm(messages_text, response.question)
        
        # Chỉ update nếu tìm thấy câu trả lời hợp lệ
        if suggested_answer.present? && !suggested_answer.include?('[Không tìm thấy') && !suggested_answer.include?('[Lỗi')
          response.update!(answer: suggested_answer, status: :approved)
          success_count += 1
        else
          failed_count += 1
        end
        
        processed += 1
      rescue StandardError => e
        Rails.logger.error "scan_all_pending error for response #{response.id}: #{e.message}"
        failed_count += 1
        processed += 1
      end
    end
    
    render json: {
      success: true,
      processed: processed,
      success: success_count,
      failed: failed_count
    }
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

  def extract_answer_with_llm(conversation_text, question)
    prompt = <<~PROMPT
      Từ đoạn hội thoại sau, hãy tìm câu trả lời cho câu hỏi.
      
      Câu hỏi: #{question}
      
      Hội thoại:
      #{conversation_text}
      
      Trả về CHỈ câu trả lời khi mà có liên quan đến câu hỏi, không giải thích thêm.
     "
    PROMPT

    Rails.logger.info("scan_answer llm_prompt_size=#{prompt.to_s.length}")

    chat = RubyLLM.chat(model: 'gpt-4o-mini')
    response = chat.ask(prompt)
    Rails.logger.info("scan_answer llm_raw_response=#{response.inspect}")
    response.content.to_s.strip
  rescue StandardError => e
    Rails.logger.error "extract_answer_with_llm error: #{e.message}"
    "[Lỗi khi extract: #{e.message}]"
  end

  def extract_messages_from_position(conversation, message_id, limit = 5)
    # Load tất cả messages vào array
    all_messages = conversation.messages.order(:created_at).to_a
    Rails.logger.info("scan_answer total_messages=#{all_messages.size} target_message_id=#{message_id} limit=#{limit}")
    
    if message_id.present?
      # Tìm index của tin nhắn có message_id
      start_index = all_messages.find_index { |m| m.id.to_s == message_id.to_s }
      Rails.logger.info("scan_answer start_index=#{start_index}")
      if start_index
        # Lấy từ vị trí message_id xuống limit tin nhắn
        messages = all_messages[start_index, limit] || []
      else
        # Không tìm thấy message_id -> lấy limit tin nhắn cuối
        messages = all_messages.last(limit)
      end
    else
      # Không có message_id -> lấy limit tin nhắn cuối
      messages = all_messages.last(limit)
    end
    Rails.logger.info("scan_answer selected_message_ids=#{messages.map(&:id)}")
    
    # Format messages thành text
    messages_text = messages.map do |msg|
      sender_type = msg.sender_type == 'Contact' ? 'Khách hàng' : 'Nhân viên'
      "#{sender_type}: #{msg.content}"
    end.join("\n")
    Rails.logger.info("scan_answer messages_text=\n#{messages_text}")

    messages_text
  end

  def extract_first_agent_reply(messages_text)
    return '' if messages_text.blank?

    lines = messages_text.split("\n").map(&:strip).reject(&:blank?)
    agent_line = lines.find { |line| line.start_with?('Nhân viên:') }
    agent_line&.sub('Nhân viên:', '')&.strip.to_s
  end
end
