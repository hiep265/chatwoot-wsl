require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::AssistantResponses', type: :request do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:document) { create(:captain_document, assistant: assistant, account: account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:another_assistant) { create(:captain_assistant, account: account) }
  let(:another_document) { create(:captain_document, account: account, assistant: assistant) }
  let(:embedding_service) { instance_double(Captain::Llm::EmbeddingService) }

  def vector_with_cosine_similarity(similarity)
    ([similarity, Math.sqrt(1 - (similarity**2))] + Array.new(1534, 0.0)).freeze
  end

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  describe 'GET /api/v1/accounts/:account_id/captain/assistant_responses' do
    context 'when no filters are applied' do
      before do
        create_list(:captain_assistant_response, 30,
                    account: account,
                    assistant: assistant,
                    documentable: document)
      end

      it 'returns first page of responses with default pagination' do
        get "/api/v1/accounts/#{account.id}/captain/assistant_responses",
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
        expect(json_response[:payload].length).to eq(25)
      end

      it 'returns second page of responses' do
        get "/api/v1/accounts/#{account.id}/captain/assistant_responses",
            params: { page: 2 },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
        expect(json_response[:payload].length).to eq(5)
        expect(json_response[:meta]).to eq({ page: 2, total_count: 30 })
      end
    end

    context 'when filtering by assistant_id' do
      before do
        create_list(:captain_assistant_response, 3,
                    account: account,
                    assistant: assistant,
                    documentable: document)
        create_list(:captain_assistant_response, 2,
                    account: account,
                    assistant: another_assistant,
                    documentable: document)
      end

      it 'returns only responses for the specified assistant' do
        get "/api/v1/accounts/#{account.id}/captain/assistant_responses",
            params: { assistant_id: assistant.id },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
        expect(json_response[:payload].length).to eq(3)
        expect(json_response[:payload][0][:assistant][:id]).to eq(assistant.id)
      end
    end

    context 'when filtering by document_id' do
      before do
        create_list(:captain_assistant_response, 3,
                    account: account,
                    assistant: assistant,
                    documentable: document)
        create_list(:captain_assistant_response, 2,
                    account: account,
                    assistant: assistant,
                    documentable: another_document)
      end

      it 'returns only responses for the specified document' do
        get "/api/v1/accounts/#{account.id}/captain/assistant_responses",
            params: { document_id: document.id },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
        expect(json_response[:payload].length).to eq(3)
        expect(json_response[:payload][0][:documentable][:id]).to eq(document.id)
      end
    end

    context 'when searching' do
      before do
        create(:captain_assistant_response,
               account: account,
               assistant: assistant,
               question: 'How to reset password?',
               answer: 'Click forgot password')
        create(:captain_assistant_response,
               account: account,
               assistant: assistant,
               question: 'How to change email?',
               answer: 'Go to settings')
      end

      it 'finds responses by question text' do
        get "/api/v1/accounts/#{account.id}/captain/assistant_responses",
            params: { search: 'password' },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
        expect(json_response[:payload].length).to eq(1)
        expect(json_response[:payload][0][:question]).to include('password')
      end

      it 'finds responses by answer text' do
        get "/api/v1/accounts/#{account.id}/captain/assistant_responses",
            params: { search: 'settings' },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
        expect(json_response[:payload].length).to eq(1)
        expect(json_response[:payload][0][:answer]).to include('settings')
      end

      it 'returns empty when no matches' do
        get "/api/v1/accounts/#{account.id}/captain/assistant_responses",
            params: { search: 'nonexistent' },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:ok)
        expect(json_response[:payload].length).to eq(0)
      end
    end
  end

  describe 'GET /api/v1/accounts/:account_id/captain/assistant_responses/:id' do
    let!(:response_record) { create(:captain_assistant_response, assistant: assistant, account: account) }

    it 'returns the requested response if the user is agent or admin' do
      get "/api/v1/accounts/#{account.id}/captain/assistant_responses/#{response_record.id}",
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response[:id]).to eq(response_record.id)
      expect(json_response[:question]).to eq(response_record.question)
      expect(json_response[:answer]).to eq(response_record.answer)
    end
  end

  describe 'GET /api/v1/accounts/:account_id/captain/assistant_responses/semantic_search' do
    before do
      allow(Captain::Llm::EmbeddingService).to receive(:new).and_return(embedding_service)
      allow(embedding_service).to receive(:get_embedding).and_return(vector_with_cosine_similarity(1.0))

      create(
        :captain_assistant_response,
        account: account,
        assistant: assistant,
        question: 'Top result',
        answer: 'Top answer',
        status: :approved,
        embedding: vector_with_cosine_similarity(0.95)
      )
      create(
        :captain_assistant_response,
        account: account,
        assistant: assistant,
        question: 'Second result',
        answer: 'Second answer',
        status: :approved,
        embedding: vector_with_cosine_similarity(0.8)
      )
      create(
        :captain_assistant_response,
        account: account,
        assistant: assistant,
        question: 'Third result',
        answer: 'Third answer',
        status: :approved,
        embedding: vector_with_cosine_similarity(0.6)
      )
      create(
        :captain_assistant_response,
        account: account,
        assistant: assistant,
        question: 'Fourth result',
        answer: 'Fourth answer',
        status: :approved,
        embedding: vector_with_cosine_similarity(0.55)
      )
      create(
        :captain_assistant_response,
        account: account,
        assistant: assistant,
        question: 'Below threshold result',
        answer: 'Below threshold answer',
        status: :approved,
        embedding: vector_with_cosine_similarity(0.4)
      )
    end

    it 'uses default min_similarity 0.5 and returns at most 3 results' do
      get "/api/v1/accounts/#{account.id}/captain/assistant_responses/semantic_search",
          params: { query: 'khóa học tiếng nhật' },
          headers: agent.create_new_auth_token,
          as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response[:payload].length).to eq(3)
      expect(json_response[:meta][:total_count]).to eq(3)
      expect(json_response[:payload].pluck(:question)).to eq(
        ['Top result', 'Second result', 'Third result']
      )
    end
  end

  describe 'POST /api/v1/accounts/:account_id/captain/assistant_responses' do
    let(:valid_params) do
      {
        assistant_response: {
          question: 'Test question?',
          answer: 'Test answer',
          assistant_id: assistant.id
        }
      }
    end

    it 'creates a new response if the user is an admin' do
      expect do
        post "/api/v1/accounts/#{account.id}/captain/assistant_responses",
             params: valid_params,
             headers: admin.create_new_auth_token,
             as: :json
      end.to change(Captain::AssistantResponse, :count).by(1)

      expect(response).to have_http_status(:success)

      expect(json_response[:question]).to eq('Test question?')
      expect(json_response[:answer]).to eq('Test answer')
    end

    context 'with invalid params' do
      let(:invalid_params) do
        {
          assistant_response: {
            question: 'Test',
            answer: 'Test'
          }
        }
      end

      it 'returns unprocessable entity status' do
        post "/api/v1/accounts/#{account.id}/captain/assistant_responses",
             params: invalid_params,
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'PATCH /api/v1/accounts/:account_id/captain/assistant_responses/:id' do
    let!(:response_record) { create(:captain_assistant_response, assistant: assistant) }
    let(:update_params) do
      {
        assistant_response: {
          question: 'Updated question?',
          answer: 'Updated answer'
        }
      }
    end

    it 'updates the response if the user is an admin' do
      patch "/api/v1/accounts/#{account.id}/captain/assistant_responses/#{response_record.id}",
            params: update_params,
            headers: admin.create_new_auth_token,
            as: :json

      expect(response).to have_http_status(:ok)

      expect(json_response[:question]).to eq('Updated question?')
      expect(json_response[:answer]).to eq('Updated answer')
    end

    context 'with invalid params' do
      let(:invalid_params) do
        {
          assistant_response: {
            question: '',
            answer: ''
          }
        }
      end

      it 'returns unprocessable entity status' do
        patch "/api/v1/accounts/#{account.id}/captain/assistant_responses/#{response_record.id}",
              params: invalid_params,
              headers: admin.create_new_auth_token,
              as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe 'DELETE /api/v1/accounts/:account_id/captain/assistant_responses/:id' do
    let!(:response_record) { create(:captain_assistant_response, assistant: assistant) }

    it 'deletes the response' do
      expect do
        delete "/api/v1/accounts/#{account.id}/captain/assistant_responses/#{response_record.id}",
               headers: admin.create_new_auth_token,
               as: :json
      end.to change(Captain::AssistantResponse, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    context 'with invalid id' do
      it 'returns not found' do
        delete "/api/v1/accounts/#{account.id}/captain/assistant_responses/0",
               headers: admin.create_new_auth_token,
               as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe 'POST /api/v1/accounts/:account_id/captain/assistant_responses/:id/scan_answer' do
    let!(:response_record) do
      create(
        :captain_assistant_response,
        account: account,
        assistant: assistant,
        documentable: create(:conversation, account: account),
        status: :pending
      )
    end

    it 'proxies scan_answer to chatbotlevan and returns the suggestion payload' do
      fake_response = instance_double(
        Net::HTTPOK,
        code: '200',
        body: {
          success: true,
          response_id: response_record.id,
          suggested_question: 'Question from backend',
          suggested_answer: 'Answer from backend'
        }.to_json
      )

      allow_any_instance_of(Api::V1::Accounts::Captain::AssistantResponsesController)
        .to receive(:chatbotlevan_base_url)
        .and_return('http://chatbotlevan.local')
      expect_any_instance_of(Api::V1::Accounts::Captain::AssistantResponsesController)
        .to receive(:post_chatbotlevan_json)
        .with(
          "http://chatbotlevan.local/learning/faq/pending/#{response_record.id}/scan",
          { account_id: account.id.to_s }
        )
        .and_return(fake_response)

      post "/api/v1/accounts/#{account.id}/captain/assistant_responses/#{response_record.id}/scan_answer",
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response[:suggested_question]).to eq('Question from backend')
      expect(json_response[:suggested_answer]).to eq('Answer from backend')
    end

    it 'maps chatbotlevan errors to bad_gateway' do
      fake_response = instance_double(
        Net::HTTPBadGateway,
        code: '502',
        body: { detail: 'upstream failed' }.to_json
      )

      allow_any_instance_of(Api::V1::Accounts::Captain::AssistantResponsesController)
        .to receive(:chatbotlevan_base_url)
        .and_return('http://chatbotlevan.local')
      allow_any_instance_of(Api::V1::Accounts::Captain::AssistantResponsesController)
        .to receive(:post_chatbotlevan_json)
        .and_return(fake_response)

      post "/api/v1/accounts/#{account.id}/captain/assistant_responses/#{response_record.id}/scan_answer",
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:bad_gateway)
      expect(json_response[:error]).to eq('upstream failed')
    end
  end

  describe 'POST /api/v1/accounts/:account_id/captain/assistant_responses/scan_all_pending' do
    it 'proxies scan_all_pending to chatbotlevan and preserves summary counts' do
      fake_response = instance_double(
        Net::HTTPOK,
        code: '200',
        body: {
          processed: 7,
          success: 5,
          failed: 2
        }.to_json
      )

      allow_any_instance_of(Api::V1::Accounts::Captain::AssistantResponsesController)
        .to receive(:chatbotlevan_base_url)
        .and_return('http://chatbotlevan.local')
      expect_any_instance_of(Api::V1::Accounts::Captain::AssistantResponsesController)
        .to receive(:post_chatbotlevan_json) do |_, url, payload|
          expect(url).to eq('http://chatbotlevan.local/learning/faq/pending/scan')
          expect(payload[:account_id].to_s).to eq(account.id.to_s)
          expect(payload[:assistant_id].to_s).to eq(assistant.id.to_s)
          fake_response
        end

      post "/api/v1/accounts/#{account.id}/captain/assistant_responses/scan_all_pending",
           params: { assistant_id: assistant.id },
           headers: admin.create_new_auth_token,
           as: :json

      expect(response).to have_http_status(:ok)
      expect(json_response[:processed]).to eq(7)
      expect(json_response[:success]).to eq(5)
      expect(json_response[:failed]).to eq(2)
    end
  end
end
