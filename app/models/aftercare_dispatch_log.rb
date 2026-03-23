class AftercareDispatchLog < ApplicationRecord
  belongs_to :aftercare_enrollment
  belongs_to :aftercare_enrollment_step
  belongs_to :message, optional: true

  validates :attempt_key, :status, :provider, presence: true
  validates :attempt_key, uniqueness: { scope: :aftercare_enrollment_step_id }

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def as_json_for_aftercare
    {
      id: id,
      attempt_key: attempt_key,
      status: status,
      provider: provider,
      provider_message_id: provider_message_id,
      message_id: message_id,
      sent_at: sent_at&.utc&.iso8601,
      error_message: error_message,
      created_at: created_at&.utc&.iso8601
    }
  end
end
