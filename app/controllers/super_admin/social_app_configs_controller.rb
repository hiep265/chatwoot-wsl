class SuperAdmin::SocialAppConfigsController < SuperAdmin::ApplicationController
  before_action :set_account
  before_action :set_config, only: [:show, :update]

  PROVIDERS = AccountSocialAppConfig::PROVIDERS
  PROVIDER_FIELDS = {
    'facebook' => %w[app_id app_secret verify_token api_version],
    'instagram' => %w[app_id app_secret verify_token api_version],
    'tiktok' => %w[app_id app_secret],
    'whatsapp_embedded' => %w[app_id app_secret configuration_id api_version],
    'twitter' => %w[app_id consumer_key consumer_secret environment]
  }.freeze

  SECRET_FIELDS = %w[app_secret verify_token consumer_secret].freeze

  def show
    @configs = @account.social_app_configs.index_by(&:provider)
  end

  def update
    errors = []
    provider = params[:provider]

    unless PROVIDERS.include?(provider)
      redirect_to super_admin_account_social_app_config_path(@account), alert: "Invalid provider: #{provider}"
      return
    end

    config = @account.social_app_configs.find_or_initialize_by(provider: provider)
    config_params = permitted_params(provider)

    # Merge settings for providers that support enable_human_agent
    if %w[facebook instagram].include?(provider) && params[:social_app_config]&.key?(:enable_human_agent)
      settings = (config.settings || {}).dup
      enable_human_agent = params.dig(:social_app_config, :enable_human_agent)
      if enable_human_agent.blank?
        settings.delete('enable_human_agent')
      else
        settings['enable_human_agent'] = ActiveModel::Type::Boolean.new.cast(enable_human_agent)
      end
      config_params[:settings] = settings
    end

    unless config.update(config_params)
      errors = config.errors.full_messages
    end

    if errors.any?
      redirect_to super_admin_account_social_app_config_path(@account), alert: errors.join(', ')
    else
      redirect_to super_admin_account_social_app_config_path(@account), notice: "#{provider.titleize} config updated successfully"
    end
  end

  def destroy
    config = @account.social_app_configs.find_by(provider: params[:provider])
    if config&.destroy
      redirect_to super_admin_account_social_app_config_path(@account), notice: "#{params[:provider].titleize} config removed"
    else
      redirect_to super_admin_account_social_app_config_path(@account), alert: 'Config not found'
    end
  end

  private

  def set_account
    @account = Account.find(params[:account_id])
  end

  def set_config
    @providers = PROVIDERS
    @provider_fields = PROVIDER_FIELDS
    @secret_fields = SECRET_FIELDS
  end

  def permitted_params(provider)
    allowed = PROVIDER_FIELDS[provider] || []
    params.require(:social_app_config).permit(allowed)
  end
end
