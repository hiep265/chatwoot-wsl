class AftercareSequenceStep < ApplicationRecord
  belongs_to :aftercare_sequence
  has_many :aftercare_enrollment_steps, dependent: :nullify

  validates :position, :title, :offset_minutes, presence: true
  validates :position, uniqueness: { scope: :aftercare_sequence_id }

  def as_json_for_aftercare
    {
      id: id,
      position: position,
      title: title,
      instructions: instructions,
      offset_minutes: offset_minutes,
      enabled: enabled
    }
  end
end
