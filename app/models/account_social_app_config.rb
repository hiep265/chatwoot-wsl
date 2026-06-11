# == Schema Information
#
# Table name: account_social_app_configs
#
#  id               :bigint           not null, primary key
#  account_id       :integer          not null
#  provider         :string           not null
#  app_id           :string
#  app_secret       :string
#  verify_token     :string
#  configuration_id :string
#  api_version      :string
#  consumer_key     :string
#  consumer_secret  :string
#  environment      :string
#  settings         :jsonb            default({})
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#
# Indexes
#
#  index_account_social_app_configs_on_account_id_and_provider  (account_id, provider) UNIQUE
#  index_account_social_app_configs_on_provider                  (provider)
#

class AccountSocialAppConfig < ApplicationRecord
  PROVIDERS = %w[facebook instagram tiktok whatsapp_embedded twitter].freeze

  belongs_to :account

  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :provider, uniqueness: { scope: :account_id }

  # Encrypt secrets when encryption is configured
  if Chatwoot.encryption_configured?
    encrypts :app_secret
    encrypts :verify_token
    encrypts :consumer_secret
  end

  store_accessor :settings, :enable_human_agent
end
