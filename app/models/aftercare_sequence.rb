class AftercareSequence < ApplicationRecord
  belongs_to :account, optional: true
  has_many :aftercare_sequence_steps, -> { order(:position, :id) }, dependent: :destroy
  has_many :aftercare_enrollments, dependent: :restrict_with_exception

  validates :code, :name, :opt_in_topic, :default_timezone, presence: true
  validates :code, uniqueness: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name, :id) }
  scope :for_account, ->(account) { where(account_id: [nil, account.id]) }

  def as_json_for_aftercare
    {
      id: id,
      code: code,
      name: name,
      description: description,
      channel_scope: channel_scope,
      opt_in_topic: opt_in_topic,
      default_timezone: default_timezone,
      active: active,
      steps: aftercare_sequence_steps.map(&:as_json_for_aftercare)
    }
  end
end
