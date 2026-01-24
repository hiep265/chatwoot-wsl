class EnableAllPremiumFeaturesForAccounts < ActiveRecord::Migration[7.0]
  def up
    # List of all premium features to enable
    premium_features = %w[
      disable_branding
      audit_logs
      sla
      custom_roles
      captain_integration
      channel_voice
      captain_integration_v2
      advanced_search
      saml
      ip_lookup
      advanced_search_indexing
      companies
      csat_review_notes
      linear_integration
      crm_integration
      notion_integration
      help_center_embedding_search
      inbound_emails
      help_center
      campaigns
      team_management
      channel_twitter
      channel_facebook
      channel_email
      channel_instagram
    ]

    # Enable all premium features for existing accounts
    Account.find_each do |account|
      account.enable_features!(*premium_features)
    end
  end

  def down
    # This migration is intentionally not reversible
    # as we want to keep all features enabled
  end
end
