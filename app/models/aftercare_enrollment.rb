class AftercareEnrollment < ApplicationRecord
  belongs_to :account
  belongs_to :conversation
  belongs_to :contact
  belongs_to :inbox
  belongs_to :aftercare_sequence
  belongs_to :created_by, class_name: 'User'

  has_many :aftercare_enrollment_steps, -> { order(:position, :id) }, dependent: :destroy
  has_many :aftercare_audit_events, dependent: :destroy
  has_many :aftercare_dispatch_logs, dependent: :destroy
  has_one :aftercare_opt_in_subscription, dependent: :destroy

  before_validation :ensure_idempotency_key, on: :create

  enum :status, {
    draft: 0,
    pending_optin: 1,
    active: 2,
    paused: 3,
    blocked_outside_window: 4,
    blocked_capability_disabled: 5,
    completed: 6,
    cancelled: 7,
    expired: 8
  }

  validates :channel_type, :channel_key, :timezone_name, :anchor_at, :idempotency_key, presence: true
  validates :idempotency_key, uniqueness: { scope: :account_id }

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def as_json_for_aftercare
    {
      id: id,
      status: status,
      channel_type: channel_type,
      channel_key: channel_key,
      staff_note: staff_note,
      timezone_name: timezone_name,
      anchor_at: anchor_at&.utc&.iso8601,
      eligibility_status: eligibility_status,
      eligibility_reason: eligibility_reason,
      eligible_until_at: eligible_until_at&.utc&.iso8601,
      last_error: last_error,
      reauthorization_required: inbox.channel.try(:reauthorization_required?) || false,
      created_at: created_at&.utc&.iso8601,
      activated_at: activated_at&.utc&.iso8601,
      conversation: {
        id: conversation_id,
        display_id: conversation.display_id
      },
      contact: {
        id: contact_id,
        name: contact.name,
        email: contact.email,
        phone_number: contact.phone_number
      },
      sequence: {
        id: aftercare_sequence_id,
        code: aftercare_sequence.code,
        name: aftercare_sequence.name
      },
      steps: aftercare_enrollment_steps.map(&:as_json_for_aftercare),
      opt_in_subscription: aftercare_opt_in_subscription&.as_json_for_aftercare
    }
  end

  private

  def ensure_idempotency_key
    return if idempotency_key.present?

    key_parts = [account_id, conversation_id, aftercare_sequence_id, anchor_at&.to_i]
    self.idempotency_key = if key_parts.all?(&:present?)
                            key_parts.join(':')
                          else
                            "#{account_id || 'aftercare'}:#{SecureRandom.uuid}"
                          end
  end
end
