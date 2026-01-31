# frozen_string_literal: true

require 'httparty'

class ContactMemoryService
  EMBEDDING_MODEL = 'text-embedding-3-small'
  EMBEDDING_DIMENSIONS = 1536
  
  def initialize(contact)
    @contact = contact
    @account = contact.account
  end
  
  # Thêm memory mới
  def add_memory(content, category: 'fact', metadata: {})
    memory = @contact.contact_memories.new(
      content: content,
      category: category,
      metadata: metadata,
      account: @account
    )
    
    if memory.save
      # Tạo embedding async (không block response)
      EmbeddingGenerationJob.perform_later(memory.id, content)
      memory
    else
      nil
    end
  end
  
  # Search với hybrid BM25 + Semantic
  def search(query, limit: 5, vector_weight: 0.7, text_weight: 0.3)
    # Tạo embedding cho query
    query_embedding = generate_embedding(query)
    
    return [] if query_embedding.blank?
    
    ContactMemory.hybrid_search(
      query: query,
      query_embedding: query_embedding,
      contact_id: @contact.id,
      limit: limit,
      vector_weight: vector_weight,
      text_weight: text_weight
    )
  end
  
  # Lấy recent memories
  def recent(limit: 10)
    @contact.contact_memories
            .order(created_at: :desc)
            .limit(limit)
  end
  
  # Lấy memories theo category
  def by_category(category, limit: 10)
    @contact.contact_memories
            .where(category: category)
            .order(created_at: :desc)
            .limit(limit)
  end
  
  # Xóa memory
  def delete_memory(memory_id)
    memory = @contact.contact_memories.find_by(id: memory_id)
    return false unless memory
    
    memory.destroy
  end
  
  # Tạo embedding cho text (synchronous - dùng cho query)
  def generate_embedding(text)
    return nil if text.blank?
    return nil if openai_api_key.blank?
    
    response = HTTParty.post(
      'https://api.openai.com/v1/embeddings',
      headers: {
        'Authorization' => "Bearer #{openai_api_key}",
        'Content-Type' => 'application/json'
      },
      body: {
        input: text,
        model: EMBEDDING_MODEL,
        dimensions: EMBEDDING_DIMENSIONS
      }.to_json,
      timeout: 30
    )
    
    if response.success?
      response['data'][0]['embedding']
    else
      Rails.logger.error "Embedding generation failed: #{response.body}"
      nil
    end
  rescue StandardError => e
    Rails.logger.error "Embedding generation error: #{e.message}"
    nil
  end
  
  class << self
    # Generate và save embedding cho memory (dùng trong job)
    def generate_and_save_embedding(memory_id)
      memory = ContactMemory.find_by(id: memory_id)
      return unless memory
      
      service = new(memory.contact)
      embedding = service.generate_embedding(memory.content)
      
      if embedding
        memory.generate_embedding!(embedding)
        memory.update_column(:search_vector, memory.send(:update_search_vector))
      end
    end
  end
  
  private
  
  def openai_api_key
    @openai_api_key ||= ENV.fetch('OPENAI_API_KEY', nil)
  end
end
