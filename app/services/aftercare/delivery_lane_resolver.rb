module Aftercare
  class DeliveryLaneResolver
    STANDARD_WINDOW = 24.hours

    class DeliveryBlockedError < StandardError
      attr_reader :reason_code, :enrollment_status, :subscription_status, :capability_status

      def initialize(message, reason_code:, enrollment_status: nil, subscription_status: nil, capability_status: nil)
        @reason_code = reason_code
        @enrollment_status = enrollment_status
        @subscription_status = subscription_status
        @capability_status = capability_status
        super(message)
      end
    end

    Result = Struct.new(
      :lane,
      :reason_code,
      :window_expires_at,
      :delivery_email,
      :token_ref,
      :subscription_id,
      :capability_status,
      keyword_init: true
    )

    def initialize(enrollment:)
      @enrollment = enrollment
      @conversation = enrollment.conversation
      @subscription = enrollment.aftercare_opt_in_subscription
    end

    def perform
      window_expires_at = standard_window_expires_at

      return Result.new(
        lane: 'standard',
        reason_code: 'within_standard_window',
        window_expires_at: window_expires_at,
        delivery_email: nil,
        token_ref: nil,
        subscription_id: @subscription&.id,
        capability_status: @subscription&.capability_status
      ) if within_standard_window?(window_expires_at)

      ensure_post_24h_delivery_allowed!

      Result.new(
        lane: 'gmail',
        reason_code: 'outside_standard_window_with_gmail_ready',
        window_expires_at: window_expires_at,
        delivery_email: delivery_email,
        token_ref: nil,
        subscription_id: @subscription.id,
        capability_status: @subscription.capability_status
      )
    end

    private

    def standard_window_expires_at
      @conversation.messages.incoming.last&.created_at&.+(STANDARD_WINDOW)
    end

    def within_standard_window?(window_expires_at)
      window_expires_at.present? && Time.current <= window_expires_at
    end

    def ensure_post_24h_delivery_allowed!
      raise_blocked!(
        'No aftercare delivery subscription found for post-24h delivery',
        reason_code: 'missing_subscription'
      ) if @subscription.blank?

      raise_blocked!(
        'Aftercare delivery is not active yet',
        reason_code: 'delivery_not_ready',
        enrollment_status: :blocked_capability_disabled
      ) unless @subscription.subscribed?

      raise_blocked!(
        'Contact email is required before aftercare can send via Gmail',
        reason_code: 'missing_contact_email',
        enrollment_status: :blocked_capability_disabled,
        subscription_status: :unsupported_channel_capability,
        capability_status: 'email_missing'
      ) if delivery_email.blank?

      raise_blocked!(
        'SMTP is not configured for Gmail aftercare delivery',
        reason_code: 'smtp_not_configured',
        enrollment_status: :blocked_capability_disabled,
        subscription_status: :unsupported_channel_capability,
        capability_status: 'smtp_not_configured'
      ) unless Aftercare::GmailDeliveryCapability.smtp_ready?
    end

    def delivery_email
      @conversation.contact.email.to_s.strip.presence
    end

    def raise_blocked!(message, reason_code:, enrollment_status: nil, subscription_status: nil, capability_status: nil)
      raise DeliveryBlockedError.new(
        message,
        reason_code: reason_code,
        enrollment_status: enrollment_status,
        subscription_status: subscription_status,
        capability_status: capability_status
      )
    end
  end
end
