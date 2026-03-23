require 'rails_helper'

RSpec.describe Aftercare::CancelEnrollmentService do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  it 'cancels the enrollment, cancels unsent steps, and records audit' do
    enrollment = create(:aftercare_enrollment, account: account, created_by: administrator, status: :active)
    scheduled_step = create(
      :aftercare_enrollment_step,
      aftercare_enrollment: enrollment,
      position: 1,
      status: :scheduled
    )
    sent_step = create(:aftercare_enrollment_step, aftercare_enrollment: enrollment, position: 2, status: :sent)

    described_class.new(enrollment: enrollment, actor: administrator).perform

    expect(enrollment.reload.status).to eq('cancelled')
    expect(enrollment.cancelled_at).to be_present
    expect(scheduled_step.reload.status).to eq('cancelled')
    expect(sent_step.reload.status).to eq('sent')
    expect(
      enrollment.aftercare_audit_events.where(event_type: 'aftercare_enrollment_cancelled').count
    ).to eq(1)
  end
end
