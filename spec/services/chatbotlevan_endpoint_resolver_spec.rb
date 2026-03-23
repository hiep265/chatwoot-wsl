# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ChatbotlevanEndpointResolver do
  describe '.chatbotlevan_base_url' do
    it 'prefers CHATBOTLEVAN_INTERNAL_BASE_URL over CHATBOTLEVAN_BASE_URL' do
      with_modified_env(
        'CHATBOTLEVAN_INTERNAL_BASE_URL' => 'http://host.docker.internal:8012/',
        'CHATBOTLEVAN_BASE_URL' => 'https://chatbotlevan2.hiep265.shop'
      ) do
        expect(described_class.chatbotlevan_base_url).to eq('http://host.docker.internal:8012')
      end
    end
  end

  describe '.captain_light_rag_url' do
    it 'falls back to CHATBOTLEVAN_INTERNAL_BASE_URL when CAPTAIN_LIGHT_RAG_URL is blank' do
      with_modified_env(
        'CAPTAIN_LIGHT_RAG_INTERNAL_URL' => '',
        'CAPTAIN_LIGHT_RAG_URL' => '',
        'CHATBOTLEVAN_INTERNAL_BASE_URL' => 'http://host.docker.internal:8012/',
        'CHATBOTLEVAN_BASE_URL' => 'https://chatbotlevan2.hiep265.shop'
      ) do
        expect(described_class.captain_light_rag_url).to eq('http://host.docker.internal:8012')
      end
    end
  end
end
