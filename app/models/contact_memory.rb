# frozen_string_literal: true

class ContactMemory < ApplicationRecord
  belongs_to :contact
  belongs_to :account
  
  validates :content, presence: true
  validates :category, inclusion: { in: %w[preference behavior context fact] }
  
  # Callbacks để tạo search_vector
  before_save :update_search_vector, if: :content_changed?
  
  # Scope cho vector similarity search
  scope :by_vector_similarity, ->(embedding_vector, threshold: 0.7, limit: 20) {
    return none if embedding_vector.blank?
    
    # Chuyển array thành vector literal cho SQL
    vector_literal = "[#{embedding_vector.join(',')}]"
    
    select("*, embedding <=> '#{vector_literal}'::vector AS distance")
      .where("embedding <=> ?::vector < ?", vector_literal, 1 - threshold)
      .order('distance ASC')
      .limit(limit)
  }
  
  # Scope cho BM25 search sử dụng PostgreSQL FTS
  scope :by_bm25, ->(query, limit: 20) {
    return none if query.blank?
    
    # Sanitize query để tránh SQL injection
    tsquery = sanitize_sql_for_conditions(["plainto_tsquery('vietnamese', ?)", query])
    
    select("*, ts_rank_cd(search_vector, #{tsquery}, 32) AS rank")
      .where("search_vector @@ plainto_tsquery('vietnamese', ?)", query)
      .order(Arel.sql("ts_rank_cd(search_vector, #{tsquery}, 32) DESC"))
      .limit(limit)
  }
  
  # Hybrid search: kết hợp vector + BM25
  def self.hybrid_search(query:, query_embedding:, contact_id:, 
                         limit: 5, 
                         vector_weight: 0.7, 
                         text_weight: 0.3,
                         candidate_multiplier: 4)
    return [] if query.blank?
    
    # Lấy candidates từ cả 2 phương pháp
    vector_limit = limit * candidate_multiplier
    text_limit = limit * candidate_multiplier
    
    # Vector search
    vector_results = where(contact_id: contact_id)
                       .by_vector_similarity(query_embedding, limit: vector_limit)
                       .to_a
    
    # BM25 search  
    text_results = where(contact_id: contact_id)
                     .by_bm25(query, limit: text_limit)
                     .to_a
    
    # Merge results theo ID
    results_map = {}
    
    # Thêm vector results
    vector_results.each do |memory|
      distance = memory.attributes['distance'] || 1.0
      vector_score = 1.0 - distance.to_f.clamp(0, 1)
      
      results_map[memory.id] = {
        memory: memory,
        vector_score: vector_score,
        bm25_score: 0.0
      }
    end
    
    # Merge BM25 results
    text_results.each do |memory|
      rank = memory.attributes['rank'] || 0.0
      bm25_score = rank.to_f.clamp(0, 1)
      
      if results_map[memory.id]
        results_map[memory.id][:bm25_score] = bm25_score
      else
        results_map[memory.id] = {
          memory: memory,
          vector_score: 0.0,
          bm25_score: bm25_score
        }
      end
    end
    
    # Tính weighted score và sort
    results = results_map.values.map do |item|
      final_score = (vector_weight * item[:vector_score]) + 
                    (text_weight * item[:bm25_score])
      
      {
        memory: item[:memory],
        final_score: final_score.round(4),
        vector_score: item[:vector_score].round(4),
        bm25_score: item[:bm25_score].round(4)
      }
    end
    
    results.sort_by { |r| -r[:final_score] }.first(limit)
  end
  
  # Tạo embedding từ content (gọi service bên ngoài)
  def generate_embedding!(embedding_vector)
    update_column(:embedding, embedding_vector)
  end
  
  private
  
  def update_search_vector
    # Tạo tsvector từ content, dùng tiếng Việt nếu có, fallback về simple
    self.search_vector = self.class.connection.execute(
      self.class.sanitize_sql_for_assignment(
        ["SELECT to_tsvector('vietnamese', ?)", content]
      )
    ).values.first&.first || ""
  rescue StandardError
    # Fallback nếu Vietnamese config không có
    self.search_vector = self.class.connection.execute(
      "SELECT to_tsvector('simple', #{self.class.connection.quote(content)})"
    ).values.first&.first || ""
  end
end
