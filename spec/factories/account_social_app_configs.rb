# frozen_string_literal: true

FactoryBot.define do
  factory :account_social_app_config do
    account
    provider { 'facebook' }
    app_id { nil }
    app_secret { nil }
    verify_token { nil }
    configuration_id { nil }
    api_version { nil }
    consumer_key { nil }
    consumer_secret { nil }
    environment { nil }
    settings { {} }
  end
end
