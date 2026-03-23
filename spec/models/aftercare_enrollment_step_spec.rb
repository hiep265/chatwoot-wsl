require 'rails_helper'

RSpec.describe AftercareEnrollmentStep, type: :model do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:enrollment) do
    create(
      :aftercare_enrollment,
      account: account,
      created_by: administrator
    )
  end

  it 'serializes recent dispatch logs for operator send history' do
    step = create(
      :aftercare_enrollment_step,
      aftercare_enrollment: enrollment,
      position: 1
    )
    older_log = AftercareDispatchLog.create!(
      aftercare_enrollment: enrollment,
      aftercare_enrollment_step: step,
      attempt_key: 'attempt-1',
      status: 'failed',
      provider: 'meta',
      error_message: 'timeout'
    )
    newer_log = AftercareDispatchLog.create!(
      aftercare_enrollment: enrollment,
      aftercare_enrollment_step: step,
      attempt_key: 'attempt-2',
      status: 'sent',
      provider: 'meta',
      sent_at: Time.current
    )

    payload = step.as_json_for_aftercare

    expect(payload[:dispatch_logs].map { |item| item[:id] }).to eq([newer_log.id, older_log.id])
    expect(payload[:latest_dispatch_log][:id]).to eq(newer_log.id)
  end
end
