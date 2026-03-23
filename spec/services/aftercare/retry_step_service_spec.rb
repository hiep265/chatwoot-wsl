require 'rails_helper'

RSpec.describe Aftercare::RetryStepService do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  before do
    clear_enqueued_jobs
  end

  it 'reschedules a failed step, clears the transient error, enqueues dispatch, and records audit' do
    enrollment = create(:aftercare_enrollment, account: account, created_by: administrator, status: :active)
    step = create(
      :aftercare_enrollment_step,
      aftercare_enrollment: enrollment,
      status: :failed,
      last_error: 'Graph API timeout'
    )

    expect do
      described_class.new(step: step, actor: administrator).perform
    end.to have_enqueued_job(Aftercare::DispatchStepJob).with(step.id)

    expect(step.reload.status).to eq('scheduled')
    expect(step.last_error).to be_blank
    expect(
      enrollment.aftercare_audit_events.where(event_type: 'aftercare_step_retry_requested').count
    ).to eq(1)
  end
end
