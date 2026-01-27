class Captain::Documents::ResponseBuilderJob < ApplicationJob
  queue_as :low

  def perform(document, options = {})
    reset_previous_responses(document)

    faqs = generate_faqs(document, options)
    create_responses_from_faqs(faqs, document)

    upsert_document_in_light_rag(document, faqs)
  end

  private

  def upsert_document_in_light_rag(document, faqs)
    client = Captain::LightRagClient.new
    unless client.enabled?
      Rails.logger.info("[Captain][LightRAG] Skipping upsert for document #{document.id}: CAPTAIN_LIGHT_RAG_URL is blank")
      return
    end

    content = build_light_rag_content(document, faqs)
    if content.blank?
      Rails.logger.info("[Captain][LightRAG] Skipping upsert for document #{document.id}: content is blank")
      return
    end

    doc_id = Captain::LightRagClient.doc_id_for_captain_document(document.id)
    Rails.logger.info("[Captain][LightRAG] Upserting document #{document.id} doc_id=#{doc_id} url=#{ENV.fetch('CAPTAIN_LIGHT_RAG_URL', '')}")

    response = client.upsert_document(
      doc_id: doc_id,
      content: content,
      file_path: document.display_url
    )

    Rails.logger.info("[Captain][LightRAG] Upsert done document #{document.id} status=#{response&.code}")
  rescue StandardError => e
    Rails.logger.error("[Captain][LightRAG] Failed to upsert document #{document.id}: #{e.message}")
  end

  def build_light_rag_content(document, faqs)
    return document.content if document.content.present?
    return '' if faqs.blank?

    faqs.map do |faq|
      question = faq['question']
      answer = faq['answer']
      "Question: #{question}\nAnswer: #{answer}"
    end.join("\n\n")
  end

  def generate_faqs(document, options)
    if should_use_pagination?(document)
      generate_paginated_faqs(document, options)
    else
      generate_standard_faqs(document)
    end
  end

  def generate_paginated_faqs(document, options)
    service = build_paginated_service(document, options)
    faqs = service.generate
    store_paginated_metadata(document, service)
    faqs
  end

  def generate_standard_faqs(document)
    Captain::Llm::FaqGeneratorService.new(document.content, document.account.locale_english_name, account_id: document.account_id).generate
  end

  def build_paginated_service(document, options)
    Captain::Llm::PaginatedFaqGeneratorService.new(
      document,
      pages_per_chunk: options[:pages_per_chunk],
      max_pages: options[:max_pages],
      language: document.account.locale_english_name
    )
  end

  def store_paginated_metadata(document, service)
    document.update!(
      metadata: (document.metadata || {}).merge(
        'faq_generation' => {
          'method' => 'paginated',
          'pages_processed' => service.total_pages_processed,
          'iterations' => service.iterations_completed,
          'timestamp' => Time.current.iso8601
        }
      )
    )
  end

  def create_responses_from_faqs(faqs, document)
    faqs.each { |faq| create_response(faq, document) }
  end

  def should_use_pagination?(document)
    # Auto-detect when to use pagination
    # For now, use pagination for PDFs with OpenAI file ID
    document.pdf_document? && document.openai_file_id.present?
  end

  def reset_previous_responses(response_document)
    response_document.responses.destroy_all
  end

  def create_response(faq, document)
    document.responses.create!(
      question: faq['question'],
      answer: faq['answer'],
      assistant: document.assistant,
      documentable: document
    )
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error I18n.t('captain.documents.response_creation_error', error: e.message)
  end
end
