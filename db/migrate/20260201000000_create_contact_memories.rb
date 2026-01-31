class CreateContactMemories < ActiveRecord::Migration[7.0]
  def up
    # Enable pgvector extension nếu chưa có
    enable_extension 'vector' unless extension_enabled?('vector')
    
    create_table :contact_memories do |t|
      t.references :contact, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      
      # Nội dung memory
      t.text :content, null: false
      t.string :category, default: 'fact'  # 'preference', 'behavior', 'context', 'fact'
      
      # Vector embedding cho semantic search (1536 dims cho OpenAI text-embedding-3-small)
      t.vector :embedding, limit: 1536
      
      # BM25 search vector
      t.tsvector :search_vector
      
      # Metadata linh hoạt
      t.jsonb :metadata, default: {}
      
      t.timestamps
    end
    
    # Indexes cho hiệu năng
    add_index :contact_memories, [:contact_id, :created_at], order: { created_at: :desc }
    add_index :contact_memories, :category
    add_index :contact_memories, :search_vector, using: :gin
    
    # HNSW index cho vector search (nhanh hơn IVFFlat)
    execute <<-SQL
      CREATE INDEX index_contact_memories_on_embedding 
      ON contact_memories 
      USING hnsw (embedding vector_cosine_ops)
      WITH (m = 16, ef_construction = 64);
    SQL
  end
  
  def down
    drop_table :contact_memories
  end
end
