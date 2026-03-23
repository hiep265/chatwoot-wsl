class AftercareOptInSubscription < ApplicationRecord
  belongs_to :aftercare_enrollment

  enum :status, {
    not_requested: 0,
    requested: 1,
    subscribed: 2,
    reoptin_required: 3,
    expired: 4,
    revoked: 5,
    unsupported_channel_capability: 6
  }

  validates :topic, :provider, :capability_status, presence: true

  def as_json_for_aftercare
    {
      id: id,
      status: status,
      topic: topic,
      provider: provider,
      capability_status: capability_status,
      token_ref: token_ref,
      requested_at: requested_at&.utc&.iso8601,
      subscribed_at: subscribed_at&.utc&.iso8601,
      expires_at: expires_at&.utc&.iso8601,
      last_error: last_error
    }
  end
end
