class Captain::Llm::AssistantChatService < Llm::BaseAiService
  include Captain::ChatHelper

  def initialize(assistant: nil, conversation_id: nil)
    super()

    @assistant = assistant
    @conversation_id = conversation_id

    @response = ''
    @tools = build_tools
    @messages = [system_message]
  end

  # additional_message: A single message (String) from the user that should be appended to the chat.
  #                    It can be an empty String or nil when you only want to supply historical messages.
  # message_history:   An Array of already formatted messages that provide the previous context.
  # role:              The role for the additional_message (defaults to `user`).
  #
  # NOTE: Parameters are provided as keyword arguments to improve clarity and avoid relying on
  # positional ordering.
  def generate_response(additional_message: nil, message_history: [], role: 'user')
    @messages += message_history
    @messages << { role: role, content: additional_message } if additional_message.present?
    request_chat_completion
  end

  def generate_playground_response(additional_message: nil, message_history: [], role: 'user')
    raw_query = additional_message.to_s.strip
    query = clean_playground_query(raw_query)
    response_text = tool_first_response_for(query, mode_hint: raw_query)

    {
      'reasoning' => nil,
      'response' => response_text
    }
  end

  private

  def tool_first_response_for(query, mode_hint: nil)
    return nil if query.blank?

    rag_response = run_rag_tools(query, mode_hint: mode_hint)
    return rag_response if rag_response.present?

    faq_response = run_faq_search(query)
    return faq_response if faq_response.present?

    queue_faq_pending(query)
    nil
  end

  def clean_playground_query(query)
    q = query.to_s.strip
    return q if q.blank?

    # Remove common “use tool <mode>” wrappers so retrieval is more accurate.
    q = q.gsub(/\A\s*dùng\s+tool\s+(naive|local|global|hybrid)\s*/i, '')
    q = q.gsub(/\A\s*use\s+tool\s+(naive|local|global|hybrid)\s*/i, '')
    q.strip
  end

  def run_rag_tools(query, mode_hint: nil)
    rag_tools = ordered_rag_tools(query, mode_hint: mode_hint)
    return nil if rag_tools.blank?

    rag_tools.each do |tool|
      result = safe_tool_execute(tool, query)
      next unless meaningful_tool_result?(result)

      return result.to_s
    end

    nil
  end

  def run_faq_search(query)
    faq_tool = @tools.find { |tool| tool.class.name.to_s == 'search_documentation' }
    return nil unless faq_tool

    result = safe_tool_execute(faq_tool, query)
    return nil unless meaningful_tool_result?(result)

    result.to_s
  end

  def safe_tool_execute(tool, query)
    # Built-in FAQ lookup tool expects `query:`
    if tool.class.name.to_s == 'search_documentation'
      return tool.execute(query: query)
    end

    # Custom HTTP tools are configured variably; try common parameter names.
    begin
      return tool.execute(query_text: query)
    rescue ArgumentError
      # e.g. unknown keyword :query_text
    end

    begin
      return tool.execute(query: query)
    rescue ArgumentError
      # unknown keyword :query
    end

    nil
  rescue StandardError => e
    Rails.logger.error("#{self.class.name} Assistant: #{@assistant.id}, Tool execution error (#{tool.class.name}): #{e.class} - #{e.message}")
    nil
  end

  def meaningful_tool_result?(result)
    text = result.to_s.strip
    return false if text.blank?

    no_result_markers = [
      'No FAQs found for the given query',
      'No relevant FAQs found',
      'An error occurred while executing the request'
    ]

    no_result_markers.none? { |marker| text.include?(marker) }
  end

  def ordered_rag_tools(query, mode_hint: nil)
    rag_tools = @tools.select { |tool| rag_tool?(tool) }
    return [] if rag_tools.blank?

    preferred = preferred_rag_mode(mode_hint || query)
    return rag_tools if preferred.blank?

    preferred_tools = rag_tools.select { |tool| tool.class.name.to_s.downcase.include?(preferred) }
    other_tools = rag_tools.reject { |tool| tool.class.name.to_s.downcase.include?(preferred) }
    preferred_tools + other_tools
  end

  def rag_tool?(tool)
    tool_name = tool.class.name.to_s
    tool_name != 'search_documentation' && tool_name.downcase.include?('rag')
  end

  def preferred_rag_mode(query)
    q = query.downcase
    return 'naive' if q.include?('naive')
    return 'hybrid' if q.include?('hybrid')
    return 'global' if q.include?('global')
    return 'local' if q.include?('local')

    nil
  end

  def queue_faq_pending(query)
    return if query.blank?
    return if @assistant.responses.pending.exists?(question: query)

    @assistant.responses.create!(
      question: query,
      answer: 'Processing',
      status: 'pending'
    )
  rescue StandardError => e
    Rails.logger.error("#{self.class.name} Assistant: #{@assistant.id}, Failed to queue FAQ pending: #{e.class} - #{e.message}")
  end

  def build_tools
    state = build_tool_state
    tools = [Captain::Tools::SearchDocumentationService.new(@assistant, user: nil)]

    selected_tool_ids = Array(@assistant.config['tool_ids']).map(&:to_s).reject(&:blank?)
    custom_tools = @assistant.account.captain_custom_tools.enabled
    custom_tools = custom_tools.where(slug: selected_tool_ids) if selected_tool_ids.any?
    custom_tools.each do |custom_tool|
      tools << custom_tool.llm_tool(@assistant, user: nil, state: state)
    end

    tools.select(&:active?)
  end

  def build_tool_state
    state = {
      account_id: @assistant.account_id,
      assistant_id: @assistant.id
    }

    return state if @conversation_id.blank?

    conversation = @assistant.account.conversations.find_by(display_id: @conversation_id)
    return state unless conversation

    state[:conversation] = {
      id: conversation.id,
      display_id: conversation.display_id
    }

    if conversation.contact
      state[:contact] = {
        id: conversation.contact.id,
        email: conversation.contact.email,
        phone_number: conversation.contact.phone_number
      }
    end

    state
  end

  def tools_summary
    @tools.map { |tool| "- #{tool.class.name}: #{tool.class.description}" }.join("\n")
  end

  def system_message
    content = if @assistant.config['system_prompt'].present?
                @assistant.config['system_prompt'].sub('{{TOOLS}}', tools_summary)
              else
                Captain::Llm::SystemPromptsService.assistant_response_generator(
                  @assistant.name,
                  @assistant.config['product_name'],
                  tools_summary,
                  @assistant.config
                )
              end

    {
      role: 'system',
      content: content
    }
  end

  def persist_message(message, message_type = 'assistant')
    # No need to implement
  end

  def feature_name
    'assistant'
  end
end
