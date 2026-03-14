# == Schema Information
#
# Table name: captain_assistant_responses
#
#  id                :bigint           not null, primary key
#  answer            :text             not null
#  documentable_type :string
#  embedding         :vector(1536)
#  question          :string           not null
#  status            :integer          default("approved"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  assistant_id      :bigint           not null
#  documentable_id   :bigint
#
# Indexes
#
#  idx_cap_asst_resp_on_documentable                  (documentable_id,documentable_type)
#  index_captain_assistant_responses_on_account_id    (account_id)
#  index_captain_assistant_responses_on_assistant_id  (assistant_id)
#  index_captain_assistant_responses_on_status        (status)
#  vector_idx_knowledge_entries_embedding             (embedding) USING ivfflat
#
class Captain::AssistantResponse < ApplicationRecord
  self.table_name = 'captain_assistant_responses'

  SCAN_METADATA_REGEX = /\A\s*\[\[scan_meta\]\](?<payload>\{.*?\})\[\[\/scan_meta\]\]\s*/m.freeze
  DEFAULT_SEARCH_LIMIT = 3
  MAX_SEARCH_LIMIT = 3
  DEFAULT_MIN_SIMILARITY = 0.5
  SEARCH_CANDIDATE_MULTIPLIER = 5

  belongs_to :assistant, class_name: 'Captain::Assistant'
  belongs_to :account
  belongs_to :documentable, polymorphic: true, optional: true
  has_neighbors :embedding, normalize: true

  validates :question, presence: true
  validates :answer, presence: true

  before_validation :ensure_account
  before_validation :ensure_status
  after_commit :update_response_embedding

  scope :ordered, -> { order(created_at: :desc) }
  scope :by_account, ->(account_id) { where(account_id: account_id) }
  scope :by_assistant, ->(assistant_id) { where(assistant_id: assistant_id) }
  scope :with_document, ->(document_id) { where(document_id: document_id) }

  enum status: { pending: 0, approved: 1 }

  def scan_metadata
    self.class.extract_scan_metadata(answer)
  end

  def display_answer
    self.class.strip_scan_metadata(answer)
  end

  def self.search(query, account_id: nil, limit: DEFAULT_SEARCH_LIMIT, min_similarity: DEFAULT_MIN_SIMILARITY)
    return none if query.blank?

    limit = DEFAULT_SEARCH_LIMIT if limit.to_i <= 0
    limit = [limit.to_i, MAX_SEARCH_LIMIT].min
    min_similarity = DEFAULT_MIN_SIMILARITY if min_similarity.to_f <= 0 || min_similarity.to_f > 1
    max_distance = 1.0 - min_similarity.to_f

    embedding = Captain::Llm::EmbeddingService.new(account_id: account_id).get_embedding(query)
    candidates_limit = [limit * SEARCH_CANDIDATE_MULTIPLIER, 20].min

    where.not(embedding: nil)
      .nearest_neighbors(:embedding, embedding, distance: 'cosine')
      .limit(candidates_limit)
      .select do |response|
        response.respond_to?(:neighbor_distance) && response.neighbor_distance.present? && response.neighbor_distance.to_f <= max_distance
      end
      .first(limit)
  end

  def self.extract_scan_metadata(raw_answer)
    text = raw_answer.to_s
    return {} if text.blank?

    scan_metadata_match = text.match(SCAN_METADATA_REGEX)
    if scan_metadata_match
      parsed = JSON.parse(scan_metadata_match[:payload]) rescue {}
      return parsed.is_a?(Hash) ? parsed.stringify_keys : {}
    end

    parsed = JSON.parse(text) rescue nil
    return {} unless parsed.is_a?(Hash)

    parsed.slice('conversation_id', 'message_id').stringify_keys
  end

  def self.strip_scan_metadata(raw_answer)
    text = raw_answer.to_s
    return '' if text.blank?

    stripped = text.sub(SCAN_METADATA_REGEX, '').strip
    return stripped if stripped != text

    parsed = JSON.parse(text) rescue nil
    return text.strip unless parsed.is_a?(Hash)

    parsed_answer = parsed['answer'].to_s.strip
    return parsed_answer if parsed_answer.present?

    metadata_keys = parsed.keys.map(&:to_s)
    return '' if (metadata_keys - %w[conversation_id message_id]).empty?

    text.strip
  end

  private

  def embedding_content
    [
      "Question: #{question.to_s.strip}",
      "Answer: #{display_answer}"
    ].join("\n")
  end

  def ensure_status
    self.status ||= :approved
  end

  def ensure_account
    self.account = assistant&.account
  end

  def update_response_embedding
    return unless saved_change_to_question? || saved_change_to_answer? || embedding.nil?

    Captain::Llm::UpdateEmbeddingJob.perform_later(self, embedding_content)
  end
end
