# frozen_string_literal: true

class CreateAccountSocialAppConfigs < ActiveRecord::Migration[7.0]
  def change
    create_table :account_social_app_configs do |t|
      t.references :account, null: false, foreign_key: true
      t.string :provider, null: false
      t.string :app_id
      t.string :app_secret
      t.string :verify_token
      t.string :configuration_id
      t.string :api_version
      t.string :consumer_key
      t.string :consumer_secret
      t.string :environment
      t.jsonb :settings, default: {}

      t.timestamps
    end

    add_index :account_social_app_configs, [:account_id, :provider], unique: true
    add_index :account_social_app_configs, :provider
  end
end
