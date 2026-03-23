require 'rails_helper'

RSpec.describe Aftercare::ProcessDueStepsJob, type: :job do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  before do
    clear_enqueued_jobs
  end

  it 'enqueues dispatch jobs for active due aftercare steps only' do
    active_enrollment = create(:aftercare_enrollment, account: account, created_by: administrator, status: :active)
    due_step = create(
      :aftercare_enrollment_step,
      aftercare_enrollment: active_enrollment,
      status: :scheduled,
      enabled: true,
      scheduled_for: 5.minutes.ago
    )
    create(
      :aftercare_enrollment_step,
      aftercare_enrollment: active_enrollment,
      status: :scheduled,
      enabled: true,
      scheduled_for: 1.hour.from_now
    )
    cancelled_enrollment = create(:aftercare_enrollment, account: account, created_by: administrator, status: :cancelled)
    create(
      :aftercare_enrollment_step,
      aftercare_enrollment: cancelled_enrollment,
      status: :scheduled,
      enabled: true,
      scheduled_for: 5.minutes.ago
    )

    expect do
      described_class.perform_now
    end.to have_enqueued_job(Aftercare::DispatchStepJob).with(due_step.id)
  end
end
