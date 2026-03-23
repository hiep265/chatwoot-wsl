class Webhooks::FacebookOptInJob < ApplicationJob
  queue_as :default

  def perform(payload)
    parsed_payload = payload.is_a?(String) ? JSON.parse(payload) : payload
    normalized_payload =
      if parsed_payload.respond_to?(:[]) && parsed_payload['messaging'].present?
        parsed_payload['messaging']
      else
        parsed_payload
      end

    Aftercare::ProcessMetaOptInEventService.new(
      payload: normalized_payload
    ).perform
  end
end
