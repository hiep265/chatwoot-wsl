module Aftercare
  class EligibilityService
    Result = Struct.new(
      :eligible,
      :reason_code,
      :channel_key,
      :channel_type,
      :window_expires_at,
      :capability_status,
      keyword_init: true
    ) do
      def to_h
        {
          eligible: eligible,
          reason_code: reason_code,
          channel_key: channel_key,
          channel_type: channel_type,
          window_expires_at: window_expires_at&.utc&.iso8601,
          capability_status: capability_status
        }
      end
    end

    def initialize(conversation:)
      @conversation = conversation
    end

    def perform
      channel_key = resolved_channel_key
      channel_type = @conversation.inbox.channel_type

      return result(false, 'unsupported_channel', channel_key:, channel_type:, capability_status: 'unsupported') if channel_key.blank?

      capability_status = capability_enabled?(channel_key) ? 'supported' : 'disabled'
      return result(false, 'channel_capability_disabled', channel_key:, channel_type:, capability_status:) unless capability_status == 'supported'

      window_expires_at = computed_window_expires_at(channel_key)
      return result(true, 'eligible', channel_key:, channel_type:, window_expires_at:, capability_status:) if within_strict_window?(window_expires_at)

      result(false, 'outside_messaging_window', channel_key:, channel_type:, window_expires_at:, capability_status:)
    end

    private

    def result(eligible, reason_code, channel_key:, channel_type:, window_expires_at: nil, capability_status:)
      Result.new(
        eligible: eligible,
        reason_code: reason_code,
        channel_key: channel_key,
        channel_type: channel_type,
        window_expires_at: window_expires_at,
        capability_status: capability_status
      )
    end

    def resolved_channel_key
      case @conversation.inbox.channel_type
      when 'Channel::FacebookPage'
        instagram_direct_message? ? 'instagram' : 'messenger'
      when 'Channel::Instagram'
        'instagram'
      else
        nil
      end
    end

    def instagram_direct_message?
      @conversation.additional_attributes.to_h['type'] == 'instagram_direct_message'
    end

    def capability_enabled?(channel_key)
      case channel_key
      when 'messenger', 'instagram'
        # Aftercare opt-in uses Marketing Messages / notification_messages, not HUMAN_AGENT.
        # Meta capability is validated when we request opt-in and later when resolving
        # the post-24h delivery lane.
        true
      else
        false
      end
    end

    def computed_window_expires_at(channel_key)
      last_incoming_message = @conversation.messages.incoming.last
      return nil unless last_incoming_message

      last_incoming_message.created_at + window_duration(channel_key)
    end

    def within_strict_window?(window_expires_at)
      window_expires_at.present? && Time.current <= window_expires_at
    end

    def window_duration(channel_key)
      24.hours
    end
  end
end
