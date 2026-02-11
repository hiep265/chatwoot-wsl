class Api::V1::Accounts::Captain::AssistantResponsesController < Api::V1::Accounts::BaseController
  before_action :current_account

  before_action :set_current_page, only: [:index]
  before_action :set_responses, except: [:create]
  before_action :set_response, only: [:show, :update, :destroy]

  RESULTS_PER_PAGE = 25
  SCAN_MESSAGES_BEFORE = 5
  SCAN_MESSAGES_AFTER = 5

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
    Rails.logger.info("scan_answer response_id=#{@response.id}")

    metadata = @response.scan_metadata
    Rails.logger.info("scan_answer metadata=#{metadata}")

    conversation_id = resolve_conversation_reference(@response, metadata)
    message_id = metadata['message_id']
    Rails.logger.info(
      "scan_answer conversation_id=#{conversation_id} message_id=#{message_id} " \
      "documentable_type=#{@response.documentable_type} documentable_id=#{@response.documentable_id}"
    )

    unless conversation_id.present?
      render json: {
        success: false,
        error: 'FAQ này không có link đến conversation gốc'
      }, status: :unprocessable_entity
      return
    end

    conversation = find_conversation(conversation_id)
    unless conversation
      render json: { success: false, error: 'Không tìm thấy conversation' }, status: :not_found
      return
    end

    question = resolved_question_for_scan(conversation, message_id, @response.question)
    Rails.logger.info("scan_answer question=#{question}")

    # Lấy context quanh message mục tiêu: 5 trước + 5 sau
    messages_text = extract_messages_from_position(
      conversation,
      message_id,
      SCAN_MESSAGES_BEFORE,
      SCAN_MESSAGES_AFTER
    )
    Rails.logger.info("scan_answer messages_text_size=#{messages_text.to_s.length}")

    # Dùng LLM để extract cả câu hỏi + câu trả lời
    scan_hints = extract_scan_hints(@response.display_answer)
    qa_suggestion = extract_faq_qa_with_llm(messages_text, question, scan_hints)
    suggested_question = qa_suggestion[:question].presence || question
    suggested_answer = qa_suggestion[:answer]
    if answer_looks_like_customer_message?(suggested_answer, messages_text)
      suggested_answer = '[Không tìm thấy câu trả lời]'
    end
    if suggested_answer.to_s.include?('[Không tìm thấy')
      fallback_answer = extract_first_human_reply_after_target(
        conversation,
        message_id,
        SCAN_MESSAGES_AFTER
      )
      fallback_answer = extract_first_agent_reply(messages_text) if fallback_answer.blank?
      suggested_answer = fallback_answer if fallback_answer.present?
    end
    Rails.logger.info(
      "scan_answer suggested_question=#{suggested_question} suggested_answer=#{suggested_answer}"
    )

    render json: {
      success: true,
      suggested_question: suggested_question,
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
        metadata = response.scan_metadata
        conversation_id = resolve_conversation_reference(response, metadata)
        message_id = metadata['message_id']

        next unless conversation_id.present?

        conversation = find_conversation(conversation_id)
        next unless conversation

        # Lấy context quanh message mục tiêu: 5 trước + 5 sau
        messages_text = extract_messages_from_position(
          conversation,
          message_id,
          SCAN_MESSAGES_BEFORE,
          SCAN_MESSAGES_AFTER
        )
        scan_hints = extract_scan_hints(response.display_answer)
        question = resolved_question_for_scan(conversation, message_id, response.question)
        qa_suggestion = extract_faq_qa_with_llm(
          messages_text,
          question,
          scan_hints
        )
        suggested_question = qa_suggestion[:question].presence || question
        suggested_answer = qa_suggestion[:answer]
        if answer_looks_like_customer_message?(suggested_answer, messages_text)
          suggested_answer = '[Không tìm thấy câu trả lời]'
        end
        if suggested_answer.to_s.include?('[Không tìm thấy')
          fallback_answer = extract_first_human_reply_after_target(
            conversation,
            message_id,
            SCAN_MESSAGES_AFTER
          )
          fallback_answer = extract_first_agent_reply(messages_text) if fallback_answer.blank?
          suggested_answer = fallback_answer if fallback_answer.present?
        end

        # Chỉ update nếu tìm thấy câu trả lời hợp lệ
        if suggested_answer.present? && !suggested_answer.include?('[Không tìm thấy') && !suggested_answer.include?('[Lỗi')
          response.update!(
            question: suggested_question,
            answer: suggested_answer,
            status: :approved
          )
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

  def resolve_conversation_reference(response, metadata)
    metadata_conversation_id = metadata['conversation_id']
    return metadata_conversation_id if metadata_conversation_id.present?
    return response.documentable_id if response.documentable_type == 'Conversation'

    nil
  end

  def extract_faq_qa_with_llm(conversation_text, current_question, scan_hints = {})
    reviewer_note = scan_hints[:reviewer_note].to_s.strip
    incorrect_bot_answer = scan_hints[:incorrect_bot_answer].to_s.strip

    prompt = <<~PROMPT
      Từ đoạn hội thoại sau, hãy tạo FAQ gồm câu hỏi và câu trả lời chính xác.
      
      Câu hỏi hiện tại: #{current_question}
      Bot answer bị đánh dấu sai: #{incorrect_bot_answer}
      Reviewer note: #{reviewer_note}
      
      Hội thoại:
      #{conversation_text}
      
      Yêu cầu:
      1) Chỉ tạo FAQ cho ĐÚNG chủ đề của "Câu hỏi hiện tại" và "Reviewer note".
      2) question: viết lại ngắn gọn theo ý khách hàng.
      3) answer: lấy câu trả lời chính xác nhất, ưu tiên từ Nhân viên (không phải Bot).
      4) Tuyệt đối KHÔNG lấy nội dung Khách hàng làm answer.
      5) Nếu không tìm thấy câu trả lời phù hợp, answer phải là: [Không tìm thấy câu trả lời].

      Trả về CHỈ JSON hợp lệ:
      {"question":"...","answer":"..."}
    PROMPT

    Rails.logger.info("scan_answer llm_prompt_size=#{prompt.to_s.length}")

    chat = RubyLLM.chat(model: 'gpt-4o-mini')
    response = chat.ask(prompt)
    raw_content = response.content.to_s.strip
    Rails.logger.info("scan_answer llm_raw_response=#{raw_content}")

    parsed = parse_llm_json_response(raw_content)
    suggested_question = parsed['question'].to_s.strip
    suggested_answer = parsed['answer'].to_s.strip

    {
      question: suggested_question.presence || current_question.to_s.strip,
      answer: suggested_answer
    }
  rescue StandardError => e
    Rails.logger.error "extract_faq_qa_with_llm error: #{e.message}"
    {
      question: current_question.to_s.strip,
      answer: "[Lỗi khi extract: #{e.message}]"
    }
  end

  def parse_llm_json_response(raw_content)
    fenced_json = raw_content.match(/```json\s*(\{.*?\})\s*```/m)
    return JSON.parse(fenced_json[1]) if fenced_json

    inline_json = raw_content.match(/\{.*\}/m)
    return JSON.parse(inline_json[0]) if inline_json

    JSON.parse(raw_content)
  end

  def resolved_question_for_scan(conversation, message_id, fallback_question)
    customer_question = extract_nearest_customer_question(conversation, message_id)
    return customer_question if customer_question.present?

    fallback_question.to_s.strip
  end

  def extract_nearest_customer_question(conversation, message_id)
    return '' if message_id.blank?

    all_messages = scan_messages_for(conversation)
    target_index = all_messages.find_index { |message| message.id.to_s == message_id.to_s }
    return '' unless target_index

    question_message = all_messages[0...target_index].reverse.find do |message|
      message.sender_type == 'Contact' && message.content.present?
    end

    question_message&.content.to_s.strip
  end

  def extract_scan_hints(display_answer)
    sections = parse_pending_answer_sections(display_answer)
    {
      incorrect_bot_answer: sections[:bot_answer].to_s.strip,
      reviewer_note: sections[:reviewer_note].to_s.strip
    }
  end

  def parse_pending_answer_sections(text)
    sections = {}
    current_key = nil
    current_lines = []

    text.to_s.each_line do |line|
      stripped = line.to_s.strip
      matched_key, inline_content = section_key_from_line(stripped)

      if matched_key
        if current_key
          sections[current_key] = current_lines.join("\n").strip
        end
        current_key = matched_key
        current_lines = []
        current_lines << inline_content if inline_content.present?
      elsif current_key
        current_lines << stripped if stripped.present?
      end
    end

    sections[current_key] = current_lines.join("\n").strip if current_key
    sections
  end

  def section_key_from_line(line)
    case line
    when /\ACustomer question:\s*(.*)\z/i
      [:customer_question, Regexp.last_match(1).to_s.strip]
    when /\ACâu hỏi khách hàng:\s*(.*)\z/i
      [:customer_question, Regexp.last_match(1).to_s.strip]
    when /\ABot answer marked as incorrect:\s*(.*)\z/i
      [:bot_answer, Regexp.last_match(1).to_s.strip]
    when /\ACâu trả lời bot bị đánh dấu sai:\s*(.*)\z/i
      [:bot_answer, Regexp.last_match(1).to_s.strip]
    when /\AReviewer note:\s*(.*)\z/i
      [:reviewer_note, Regexp.last_match(1).to_s.strip]
    when /\AGhi chú reviewer:\s*(.*)\z/i
      [:reviewer_note, Regexp.last_match(1).to_s.strip]
    when /\AGhi chú đánh giá:\s*(.*)\z/i
      [:reviewer_note, Regexp.last_match(1).to_s.strip]
    else
      [nil, nil]
    end
  end

  def answer_looks_like_customer_message?(answer_text, messages_text)
    normalized_answer = normalize_scan_text(answer_text)
    return false if normalized_answer.blank?

    customer_messages = messages_text.to_s.lines.filter_map do |line|
      stripped = line.to_s.strip
      next unless stripped.start_with?('Khách hàng:')

      normalize_scan_text(stripped.sub('Khách hàng:', ''))
    end

    customer_messages.any? do |customer_message|
      customer_message.present? &&
        (customer_message == normalized_answer ||
         customer_message.include?(normalized_answer) ||
         normalized_answer.include?(customer_message))
    end
  end

  def normalize_scan_text(text)
    text.to_s.downcase.gsub(/\s+/, ' ').strip
  end

  def extract_messages_from_position(conversation, message_id, before_limit = 5, after_limit = 5)
    # Load chỉ tin nhắn chat thật (không activity/private/log trống)
    all_messages = scan_messages_for(conversation)
    Rails.logger.info(
      "scan_answer total_messages=#{all_messages.size} " \
      "target_message_id=#{message_id} before_limit=#{before_limit} after_limit=#{after_limit}"
    )

    before_count = [before_limit.to_i, 0].max
    after_count = [after_limit.to_i, 0].max
    window_size = before_count + after_count + 1

    if message_id.present?
      # Tìm index của tin nhắn có message_id
      target_index = all_messages.find_index { |m| m.id.to_s == message_id.to_s }
      Rails.logger.info("scan_answer target_index=#{target_index}")
      if target_index
        context_start = [target_index - before_count, 0].max
        context_end = [target_index + after_count, all_messages.size - 1].min
        messages = all_messages[context_start..context_end] || []
      else
        # Không tìm thấy message_id -> lấy context cuối cùng
        messages = all_messages.last(window_size)
      end
    else
      # Không có message_id -> lấy context cuối cùng
      messages = all_messages.last(window_size)
    end
    Rails.logger.info("scan_answer selected_message_ids=#{messages.map(&:id)}")

    # Format messages thành text
    messages_text = messages.map do |msg|
      sender_type = scan_sender_label(msg)
      "#{sender_type}: #{msg.content}"
    end.join("\n")
    Rails.logger.info("scan_answer messages_text=\n#{messages_text}")

    messages_text
  end

  def scan_sender_label(message)
    return 'Khách hàng' if message.sender_type == 'Contact'
    return 'Bot' if bot_generated_message?(message)

    'Nhân viên'
  end

  def bot_generated_message?(message)
    attributes = message.content_attributes
    attributes = JSON.parse(attributes) if attributes.is_a?(String)
    return false unless attributes.is_a?(Hash)

    raw_flag = attributes['is_bot_generated']
    raw_flag = attributes[:is_bot_generated] if raw_flag.nil?

    ActiveModel::Type::Boolean.new.cast(raw_flag)
  rescue JSON::ParserError
    false
  end

  def extract_first_agent_reply(messages_text)
    return '' if messages_text.blank?

    lines = messages_text.split("\n").map(&:strip).reject(&:blank?)
    agent_line = lines.reverse.find { |line| line.start_with?('Nhân viên:') }
    agent_line&.sub('Nhân viên:', '')&.strip.to_s
  end

  def extract_first_human_reply_after_target(conversation, message_id, after_limit = 5)
    return '' if message_id.blank?

    all_messages = scan_messages_for(conversation)
    target_index = all_messages.find_index { |message| message.id.to_s == message_id.to_s }
    return '' unless target_index

    trailing_messages = all_messages[(target_index + 1), [after_limit.to_i, 0].max] || []
    human_reply = trailing_messages.find do |message|
      message.content.present? &&
        message.sender_type != 'Contact' &&
        !bot_generated_message?(message)
    end

    human_reply&.content.to_s.strip
  end

  def scan_messages_for(conversation)
    conversation.messages.chat.reorder(:created_at).to_a.select do |message|
      message.content.to_s.strip.present?
    end
  end
end
