require 'rails_helper'

RSpec.describe Captain::AssistantResponse, type: :model do
  include ActiveJob::TestHelper

  let(:assistant) { create(:captain_assistant) }
  let(:embedding_service) { instance_double(Captain::Llm::EmbeddingService) }

  def vector_with_cosine_similarity(similarity)
    ([similarity, Math.sqrt(1 - (similarity**2))] + Array.new(1534, 0.0)).freeze
  end

  around do |example|
    clear_enqueued_jobs
    clear_performed_jobs
    example.run
    clear_enqueued_jobs
    clear_performed_jobs
  end

  describe 'embedding updates' do
    it 'enqueues embedding generation with both question and answer on create' do
      expect do
        create(
          :captain_assistant_response,
          assistant: assistant,
          account: assistant.account,
          question: 'Khóa học có bản tiếng Nhật không?',
          answer: 'Khóa học hiện có tài liệu hỗ trợ bằng tiếng Nhật.'
        )
      end.to have_enqueued_job(Captain::Llm::UpdateEmbeddingJob).with(
        instance_of(Captain::AssistantResponse),
        "Question: Khóa học có bản tiếng Nhật không?\nAnswer: Khóa học hiện có tài liệu hỗ trợ bằng tiếng Nhật."
      ).on_queue('low')
    end

    it 'rebuilds embedding content from the updated answer, not just the question' do
      response = create(
        :captain_assistant_response,
        assistant: assistant,
        account: assistant.account,
        question: 'What should I do first when I receive the online materials?',
        answer: 'Please read the guide first.'
      )

      clear_enqueued_jobs

      expect do
        response.update!(answer: 'Please read the guide first. The Japan section is prepared in Japanese.')
      end.to have_enqueued_job(Captain::Llm::UpdateEmbeddingJob).with(
        response,
        "Question: What should I do first when I receive the online materials?\nAnswer: Please read the guide first. The Japan section is prepared in Japanese."
      ).on_queue('low')
    end

    it 'strips scan metadata from the answer before generating embeddings' do
      response = build(
        :captain_assistant_response,
        assistant: assistant,
        account: assistant.account,
        question: 'Where is the source answer stored?',
        answer: '[[scan_meta]]{"conversation_id":114,"message_id":3475}[[/scan_meta]]Nội dung trả lời thật'
      )

      expect(response.send(:embedding_content)).to eq(
        "Question: Where is the source answer stored?\nAnswer: Nội dung trả lời thật"
      )
    end
  end

  describe '.search' do
    before do
      allow(Captain::Llm::EmbeddingService).to receive(:new).and_return(embedding_service)
      allow(embedding_service).to receive(:get_embedding).and_return(vector_with_cosine_similarity(1.0))
    end

    it 'returns at most 3 results above the default 0.5 similarity threshold' do
      high_match = create(
        :captain_assistant_response,
        assistant: assistant,
        account: assistant.account,
        question: 'High match',
        answer: 'High answer',
        status: :approved,
        embedding: vector_with_cosine_similarity(0.99)
      )
      medium_match = create(
        :captain_assistant_response,
        assistant: assistant,
        account: assistant.account,
        question: 'Medium match',
        answer: 'Medium answer',
        status: :approved,
        embedding: vector_with_cosine_similarity(0.75)
      )
      low_pass_match = create(
        :captain_assistant_response,
        assistant: assistant,
        account: assistant.account,
        question: 'Low pass match',
        answer: 'Low pass answer',
        status: :approved,
        embedding: vector_with_cosine_similarity(0.6)
      )
      fourth_match = create(
        :captain_assistant_response,
        assistant: assistant,
        account: assistant.account,
        question: 'Fourth match',
        answer: 'Fourth answer',
        status: :approved,
        embedding: vector_with_cosine_similarity(0.52)
      )
      create(
        :captain_assistant_response,
        assistant: assistant,
        account: assistant.account,
        question: 'Below threshold',
        answer: 'Below threshold answer',
        status: :approved,
        embedding: vector_with_cosine_similarity(0.4)
      )

      results = assistant.responses.approved.search('bản tiếng nhật')

      expect(results.map(&:id)).to eq([high_match.id, medium_match.id, low_pass_match.id])
      expect(results.length).to eq(3)
      expect(results).not_to include(fourth_match)
    end
  end
end
