# frozen_string_literal: true

class ChatbotlevanEndpointResolver
  class << self
    def chatbotlevan_base_url
      resolve_url(
        'CHATBOTLEVAN_INTERNAL_BASE_URL',
        'CHATBOTLEVAN_BASE_URL'
      )
    end

    def captain_light_rag_url
      resolve_url(
        'CAPTAIN_LIGHT_RAG_INTERNAL_URL',
        'CAPTAIN_LIGHT_RAG_URL',
        'CHATBOTLEVAN_INTERNAL_BASE_URL',
        'CHATBOTLEVAN_BASE_URL'
      )
    end

    private

    def resolve_url(*keys)
      keys.each do |key|
        value = ENV.fetch(key, '').to_s.strip.chomp('/')
        return value if value.present?
      end

      ''
    end
  end
end
