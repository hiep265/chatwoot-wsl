class AccountSocialAppConfigResolver
  MAPPING = {
    # Facebook
    'FB_APP_ID' => { provider: 'facebook', field: :app_id },
    'FB_APP_SECRET' => { provider: 'facebook', field: :app_secret },
    'FB_VERIFY_TOKEN' => { provider: 'facebook', field: :verify_token },
    'FACEBOOK_API_VERSION' => { provider: 'facebook', field: :api_version },
    'ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT' => { provider: 'facebook', field: :enable_human_agent, settings: true },
    # Instagram
    'INSTAGRAM_APP_ID' => { provider: 'instagram', field: :app_id },
    'INSTAGRAM_APP_SECRET' => { provider: 'instagram', field: :app_secret },
    'INSTAGRAM_VERIFY_TOKEN' => { provider: 'instagram', field: :verify_token },
    'INSTAGRAM_API_VERSION' => { provider: 'instagram', field: :api_version },
    'ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT' => { provider: 'instagram', field: :enable_human_agent, settings: true },
    # TikTok
    'TIKTOK_APP_ID' => { provider: 'tiktok', field: :app_id },
    'TIKTOK_APP_SECRET' => { provider: 'tiktok', field: :app_secret },
    # WhatsApp Embedded Signup
    'WHATSAPP_APP_ID' => { provider: 'whatsapp_embedded', field: :app_id },
    'WHATSAPP_APP_SECRET' => { provider: 'whatsapp_embedded', field: :app_secret },
    'WHATSAPP_CONFIGURATION_ID' => { provider: 'whatsapp_embedded', field: :configuration_id },
    'WHATSAPP_API_VERSION' => { provider: 'whatsapp_embedded', field: :api_version },
    # Twitter/X
    'TWITTER_APP_ID' => { provider: 'twitter', field: :app_id },
    'TWITTER_CONSUMER_KEY' => { provider: 'twitter', field: :consumer_key },
    'TWITTER_CONSUMER_SECRET' => { provider: 'twitter', field: :consumer_secret },
    'TWITTER_ENVIRONMENT' => { provider: 'twitter', field: :environment }
  }.freeze

  # Cache config records per instance to avoid repeated lookups
  attr_reader :account

  def initialize(account)
    @account = account
    @loaded_configs = {}
  end

  # Resolve a config key, checking account-level override first,
  # then falling back to global config.
  #
  # Usage:
  #   AccountSocialAppConfigResolver.new(account).load('FB_APP_ID', '')
  #   AccountSocialAppConfigResolver.new(account).load('TIKTOK_APP_SECRET', nil)
  def load(config_key, default_value)
    mapping_entry = MAPPING[config_key]
    return GlobalConfigService.load(config_key, default_value) unless mapping_entry

    config = config_for(mapping_entry[:provider])
    return GlobalConfigService.load(config_key, default_value) unless config

    value = if mapping_entry[:settings]
              setting_value(config, mapping_entry[:field])
            else
              config.public_send(mapping_entry[:field])
            end

    blank_config_value?(value) ? GlobalConfigService.load(config_key, default_value) : value
  end

  # Load multiple config keys at once, returning a hash.
  # Usage:
  #   AccountSocialAppConfigResolver.new(account).load_many('FB_APP_ID' => '', 'FB_APP_SECRET' => '')
  def load_many(mapping = {})
    mapping.each_with_object({}) do |(key, default), result|
      result[key] = load(key, default)
    end
  end

  private

  def config_for(provider)
    return nil if @account.nil?

    @loaded_configs[provider] ||= AccountSocialAppConfig.find_by(account: @account, provider: provider)
  end

  def setting_value(config, field)
    field_name = field.to_s
    return nil unless config.settings&.key?(field_name)

    config.settings[field_name]
  end

  def blank_config_value?(value)
    value.nil? || (value.is_a?(String) && value.strip.empty?) || (value.respond_to?(:empty?) && value.empty?)
  end
end
