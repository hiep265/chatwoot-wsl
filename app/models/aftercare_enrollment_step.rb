class AftercareEnrollmentStep < ApplicationRecord
  belongs_to :aftercare_enrollment
  belongs_to :aftercare_sequence_step, optional: true
  has_many :aftercare_dispatch_logs, dependent: :destroy

  enum :status, {
    draft_pending: 0,
    draft_ready: 1,
    scheduled: 2,
    sending: 3,
    sent: 4,
    failed: 5,
    cancelled: 6,
    skipped: 7
  }, prefix: :status

  enum :draft_status, {
    not_requested: 0,
    pending: 1,
    ready: 2,
    failed_generation: 3
  }, prefix: :draft

  validates :position, :title, :offset_minutes, :scheduled_for, presence: true
  validates :position, uniqueness: { scope: :aftercare_enrollment_id }

  def as_json_for_aftercare
    recent_dispatch_logs = aftercare_dispatch_logs.recent_first.limit(3)

    {
      id: id,
      position: position,
      title: title,
      instructions: instructions,
      status: status,
      draft_status: draft_status,
      draft_body: draft_body,
      draft_summary: draft_summary,
      draft_version: draft_version,
      draft_generated_at: draft_generated_at&.utc&.iso8601,
      draft_input_snapshot: draft_input_snapshot,
      draft_error: draft_error,
      offset_minutes: offset_minutes,
      scheduled_for: scheduled_for&.utc&.iso8601,
      step_note: step_note,
      enabled: enabled,
      last_error: last_error,
      latest_dispatch_log: recent_dispatch_logs.first&.as_json_for_aftercare,
      dispatch_logs: recent_dispatch_logs.map(&:as_json_for_aftercare)
    }
  end
end
