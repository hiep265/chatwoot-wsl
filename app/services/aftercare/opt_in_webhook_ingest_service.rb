module Aftercare
  class OptInWebhookIngestService
    def initialize(subscription:, event_name:, token_ref: nil, occurred_at: nil, expires_at: nil, payload: {})
      @subscription = subscription
      @enrollment = subscription.aftercare_enrollment
      @event_name = event_name.to_s
      @token_ref = token_ref
      @occurred_at = occurred_at.presence
      @expires_at = expires_at.presence
      @payload = payload.presence || {}
    end

    def perform
      ActiveRecord::Base.transaction do
        case @event_name
        when 'opt_in.subscribed'
          @subscription.update!(
            status: :subscribed,
            token_ref: @token_ref.presence || @subscription.token_ref,
            subscribed_at: parsed_time(@occurred_at) || Time.current,
            expires_at: parsed_time(@expires_at),
            webhook_payload: @payload,
            last_error: nil
          )
          @enrollment.update!(
            status: :active,
            activated_at: parsed_time(@occurred_at) || Time.current,
            last_error: nil
          )
        when 'opt_in.expired'
          @subscription.update!(
            status: :expired,
            expires_at: parsed_time(@expires_at) || parsed_time(@occurred_at) || Time.current,
            webhook_payload: @payload,
            last_error: 'opt-in expired'
          )
          @enrollment.update!(status: :expired, last_error: 'opt-in expired')
        when 'opt_in.revoked'
          @subscription.update!(
            status: :revoked,
            revoked_at: parsed_time(@occurred_at) || Time.current,
            webhook_payload: @payload,
            last_error: 'opt-in revoked'
          )
          @enrollment.update!(status: :expired, last_error: 'opt-in revoked')
        when 'opt_in.reoptin_required'
          @subscription.update!(
            status: :reoptin_required,
            webhook_payload: @payload,
            last_error: 're-optin required'
          )
          @enrollment.update!(status: :paused, last_error: 're-optin required')
        else
          raise ArgumentError, "Unsupported opt-in event: #{@event_name}"
        end

        AuditService.record!(
          account: @enrollment.account,
          enrollment: @enrollment,
          actor: nil,
          event_type: "aftercare_#{@event_name.tr('.', '_')}",
          payload: {
            subscription_id: @subscription.id,
            token_ref: @token_ref,
            event_name: @event_name
          }.merge(@payload.is_a?(Hash) ? @payload : {})
        )
      end

      {
        subscription: @subscription.reload,
        enrollment: @enrollment.reload
      }
    end

    private

    def parsed_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue StandardError
      nil
    end
  end
end
