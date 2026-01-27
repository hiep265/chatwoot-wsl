class Captain::Documents::LightRagDeleteJob < ApplicationJob
  queue_as :low

  def perform(doc_id, delete_llm_cache: false)
    client = Captain::LightRagClient.new
    return unless client.enabled?

    client.delete_document(doc_id: doc_id, delete_llm_cache: delete_llm_cache)
  rescue StandardError => e
    Rails.logger.error("[Captain][LightRAG] Failed to delete doc_id=#{doc_id}: #{e.message}")
  end
end
