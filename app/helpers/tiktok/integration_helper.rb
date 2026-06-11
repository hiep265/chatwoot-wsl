module Tiktok::IntegrationHelper
  # Generates a signed JWT token for Tiktok integration
  #
  # @param account_id [Integer] The account ID to encode in the token
  # @return [String, nil] The encoded JWT token or nil if client secret is missing
  def generate_tiktok_token(account_id)
    secret = secret_for_account_id(account_id)
    return if secret.blank?

    JWT.encode(token_payload(account_id), secret, 'HS256')
  rescue StandardError => e
    Rails.logger.error("Failed to generate TikTok token: #{e.message}")
    nil
  end

  # Verifies and decodes a Tiktok JWT token
  # Supports both global and account-level TikTok app secrets
  #
  # @param token [String] The JWT token to verify
  # @return [Integer, nil] The account ID from the token or nil if invalid
  def verify_tiktok_token(token)
    return if token.blank?

    decoded_account_id = unverified_account_id(token)
    return nil unless decoded_account_id

    secrets_for_account_id(decoded_account_id).each do |secret|
      decoded_value = decode_token(token, secret, log_errors: false)
      return decoded_value if decoded_value
    end

    nil
  rescue StandardError => e
    Rails.logger.error("Unexpected error verifying Tiktok token: #{e.message}")
    nil
  end

  private

  def client_secret
    @client_secret ||= GlobalConfigService.load('TIKTOK_APP_SECRET', nil)
  end

  def secret_for_account_id(account_id)
    secrets_for_account_id(account_id).first
  end

  def secrets_for_account_id(account_id)
    account = Account.find_by(id: account_id)
    account_secret = AccountSocialAppConfigResolver.new(account).load('TIKTOK_APP_SECRET', nil) if account

    [account_secret, client_secret].compact_blank.uniq
  end

  def token_payload(account_id)
    {
      sub: account_id,
      iat: Time.current.to_i
    }
  end

  def unverified_account_id(token)
    payload, = JWT.decode(token, nil, false, { algorithm: 'HS256' })
    payload['sub']
  rescue StandardError => e
    Rails.logger.error("Unexpected error verifying Tiktok token: #{e.message}")
    nil
  end

  def decode_token(token, secret, log_errors: true)
    JWT.decode(token, secret, true, {
                 algorithm: 'HS256',
                 verify_expiration: true
               }).first['sub']
  rescue StandardError => e
    Rails.logger.error("Unexpected error verifying Tiktok token: #{e.message}") if log_errors
    nil
  end
end
