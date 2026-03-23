require 'rails_helper'

RSpec.describe Aftercare::PauseEnrollmentService do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  it 'pauses an active enrollment, keeps sent steps untouched, and records audit' do
    enrollment = create(
      :aftercare_enrollment,
      account: account,
      created_by: administrator,
      status: :active
    )
    scheduled_step = create(
      :aftercare_enrollment_step,
      aftercare_enrollment: enrollment,
      position: 1,
      status: :scheduled
    )
    sent_step = create(
      :aftercare_enrollment_step,
      aftercare_enrollment: enrollment,
      position: 2,
      status: :sent
    )

    described_class.new(enrollment: enrollment, actor: administrator).perform

    expect(enrollment.reload.status).to eq('paused')
    expect(enrollment.paused_at).to be_present
    expect(scheduled_step.reload.status).to eq('scheduled')
    expect(sent_step.reload.status).to eq('sent')
    expect(
      enrollment.aftercare_audit_events.where(event_type: 'aftercare_enrollment_paused').count
    ).to eq(1)
  end
end
