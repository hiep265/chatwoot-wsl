require 'cgi'
require 'digest/sha1'
require 'httparty'

class Captain::LightRagClient
  DEFAULT_TIMEOUT = 10

  NAMESPACE_UUID = '6ba7b810-9dad-11d1-80b4-00c04fd430c8'.freeze

  def self.doc_id_for_captain_document(document_id)
    uuid_v5(NAMESPACE_UUID, "chatwoot_captain_document:#{document_id}")
  end

  def self.uuid_v5(namespace_uuid, name)
    namespace_bytes = [namespace_uuid.delete('-')].pack('H*')
    digest = Digest::SHA1.digest(namespace_bytes + name.to_s)
    bytes = digest.bytes.first(16)

    bytes[6] = (bytes[6] & 0x0f) | 0x50
    bytes[8] = (bytes[8] & 0x3f) | 0x80

    hex = bytes.pack('C*').unpack1('H*')
    "#{hex[0, 8]}-#{hex[8, 4]}-#{hex[12, 4]}-#{hex[16, 4]}-#{hex[20, 12]}"
  end

  def initialize(
    base_url: ENV.fetch('CAPTAIN_LIGHT_RAG_URL', nil),
    api_key: ENV.fetch('CAPTAIN_LIGHT_RAG_API_KEY', nil),
    timeout: ENV.fetch('CAPTAIN_LIGHT_RAG_TIMEOUT', DEFAULT_TIMEOUT).to_i
  )
    @base_url = base_url.to_s.strip
    @api_key = api_key.to_s.strip
    @timeout = timeout
  end

  def enabled?
    @base_url.present?
  end

  def upsert_document(doc_id:, content:, file_path: nil)
    return unless enabled?

    payload = {
      documents: [content.to_s],
      ids: [doc_id.to_s]
    }

    if file_path.present?
      payload[:file_paths] = [file_path.to_s]
    end

    url = build_url('/rag/insert')
    Rails.logger.info("[Captain][LightRAG] POST #{url} doc_id=#{doc_id}")

    response = HTTParty.post(
      url,
      headers: headers.merge('Content-Type' => 'application/json'),
      body: payload.to_json,
      timeout: @timeout
    )

    return response if response.success?

    raise "LightRAG upsert failed status=#{response.code} body=#{response.body}"
  end

  def delete_document(doc_id:, delete_llm_cache: false)
    return unless enabled?

    encoded_doc_id = CGI.escape(doc_id.to_s)
    url = build_url("/rag/documents/#{encoded_doc_id}")

    Rails.logger.info("[Captain][LightRAG] DELETE #{url} doc_id=#{doc_id}")

    response = HTTParty.delete(
      url,
      query: { delete_llm_cache: delete_llm_cache },
      headers: headers,
      timeout: @timeout
    )

    return response if response.success? || response.code.to_i == 404

    raise "LightRAG delete failed status=#{response.code} body=#{response.body}"
  end

  private

  def headers
    return {} if @api_key.blank?

    { 'Authorization' => "Bearer #{@api_key}" }
  end

  def build_url(path)
    base = @base_url.delete_suffix('/')
    "#{base}#{path}"
  end
end
