# frozen_string_literal: true

# Background job để tạo embedding cho memory
# Không block API response
class EmbeddingGenerationJob < ApplicationJob
  queue_as :default
  
  retry_on StandardError, wait: :exponentially_longer, attempts: 3
  
  def perform(memory_id, content = nil)
    memory = ContactMemory.find_by(id: memory_id)
    return unless memory
    
    # Dùng content được truyền vào hoặc từ memory
    text = content || memory.content
    
    service = ContactMemoryService.new(memory.contact)
    embedding = service.generate_embedding(text)
    
    if embedding
      memory.generate_embedding!(embedding)
      Rails.logger.info "Generated embedding for memory #{memory_id}"
    else
      Rails.logger.error "Failed to generate embedding for memory #{memory_id}"
    end
  end
end
