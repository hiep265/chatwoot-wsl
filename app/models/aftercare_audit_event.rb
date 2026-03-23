class AftercareAuditEvent < ApplicationRecord
  belongs_to :account
  belongs_to :aftercare_enrollment, optional: true
  belongs_to :actor, polymorphic: true, optional: true

  validates :event_type, presence: true
end
