module Aftercare
  class AuditService
    def self.record!(account:, enrollment:, event_type:, actor: nil, payload: {})
      AftercareAuditEvent.create!(
        account: account,
        aftercare_enrollment: enrollment,
        actor: actor,
        event_type: event_type,
        payload: payload
      )
    end
  end
end
