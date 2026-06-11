class Webhooks::TiktokController < ActionController::API
  before_action :verify_signature!

  def events
    event = JSON.parse(request_payload)
    if echo_event?
      # Add delay to prevent race condition where echo arrives before send message API completes
      # This avoids duplicate messages when echo comes early during API processing
      ::Webhooks::TiktokEventsJob.set(wait: 2.seconds).perform_later(event)
    else
      ::Webhooks::TiktokEventsJob.perform_later(event)
    end

    head :ok
  end

  private

  def request_payload
    @request_payload ||= request.body.read
  end

  def verify_signature!
    signature_header = request.headers['Tiktok-Signature']
    received_timestamp, received_signature = extract_signature_parts(signature_header)

    return head :unauthorized unless received_timestamp && received_signature

    # Try all configured TikTok secrets (account-level + global fallback)
    valid = tiktok_secrets.any? do |secret|
      signature_payload = "#{received_timestamp}.#{request_payload}"
      computed_signature = OpenSSL::HMAC.hexdigest('SHA256', secret, signature_payload)
      ActiveSupport::SecurityUtils.secure_compare(computed_signature, received_signature)
    end

    return head :unauthorized unless valid

    # Check timestamp delay (acceptable delay: 5 seconds)
    current_timestamp = Time.current.to_i
    delay = current_timestamp - received_timestamp

    return head :unauthorized if delay > 5
  end

  def extract_signature_parts(signature_header)
    return [nil, nil] if signature_header.blank?

    keys = signature_header.split(',')
    signature_parts = keys.map { |part| part.split('=') }.to_h
    [signature_parts['t']&.to_i, signature_parts['s']]
  end

  def echo_event?
    params[:event] == 'im_send_msg'
  end

  def tiktok_secrets
    global_secret = GlobalConfigService.load('TIKTOK_APP_SECRET', nil)
    account_secrets = AccountSocialAppConfig.where(provider: 'tiktok').filter_map(&:app_secret)
    secrets = account_secrets
    secrets << global_secret if global_secret.present?
    secrets
  end
end
