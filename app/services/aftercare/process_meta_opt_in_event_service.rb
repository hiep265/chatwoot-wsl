module Aftercare
  class ProcessMetaOptInEventService
    def initialize(payload:, channel: nil)
      @payload = payload.to_h.with_indifferent_access
      @channel = channel
    end

    def perform
      return if optin_payload.blank?
      return unless notification_messages_optin?

      subscription = resolve_subscription
      return if subscription.blank?

      Aftercare::OptInWebhookIngestService.new(
        subscription: subscription,
        event_name: normalized_event_name,
        token_ref: notification_messages_token,
        occurred_at: occurred_at,
        expires_at: expires_at,
        payload: normalized_payload
      ).perform
    end

    private

    def resolve_subscription
      subscription_id = correlation_payload[:aftercare_subscription_id].presence
      return nil if subscription_id.blank?

      scope = AftercareOptInSubscription.joins(:aftercare_enrollment)
      scope = scope.where(aftercare_enrollments: { account_id: resolved_channel.account_id }) if resolved_channel.present?
      scope.find_by(id: subscription_id)
    end

    def resolved_channel
      @channel ||= begin
        recipient_id = @payload.dig(:recipient, :id).to_s
        Channel::FacebookPage.find_by(page_id: recipient_id) ||
          Channel::Instagram.find_by(instagram_id: recipient_id)
      end
    end

    def optin_payload
      @optin_payload ||= @payload[:optin].presence&.with_indifferent_access || {}
    end

    def correlation_payload
      @correlation_payload ||= begin
        raw_payload = optin_payload[:payload]
        parsed_payload =
          if raw_payload.is_a?(String)
            JSON.parse(raw_payload)
          elsif raw_payload.respond_to?(:to_h)
            raw_payload.to_h
          else
            {}
          end

        parsed_payload.with_indifferent_access
      rescue JSON::ParserError
        {}.with_indifferent_access
      end
    end

    def notification_messages_optin?
      optin_payload[:type].to_s == 'notification_messages'
    end

    def notification_messages_token
      optin_payload[:notification_messages_token].presence
    end

    def notification_messages_status
      optin_payload[:notification_messages_status].to_s.presence
    end

    def normalized_event_name
      case notification_messages_status
      when 'STOP NOTIFICATIONS'
        'opt_in.revoked'
      when 'RESUME NOTIFICATIONS'
        'opt_in.subscribed'
      else
        'opt_in.subscribed'
      end
    end

    def occurred_at
      parsed_unix_timestamp(@payload[:timestamp])
    end

    def expires_at
      parsed_unix_timestamp(optin_payload[:token_expiry_timestamp])
    end

    def parsed_unix_timestamp(value)
      return nil if value.blank?

      timestamp = value.to_f
      timestamp /= 1000.0 if timestamp > 10_000_000_000

      Time.zone.at(timestamp).iso8601
    rescue StandardError
      nil
    end

    def normalized_payload
      {
        source: 'meta_optin_webhook',
        channel_type: resolved_channel&.class&.name,
        sender_id: @payload.dig(:sender, :id),
        recipient_id: @payload.dig(:recipient, :id),
        correlation_payload: correlation_payload.to_h,
        raw_payload: @payload.deep_stringify_keys
      }.merge(optin_payload.deep_stringify_keys)
    end
  end
end
