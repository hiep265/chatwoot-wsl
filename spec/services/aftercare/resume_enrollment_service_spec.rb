require 'rails_helper'

RSpec.describe Aftercare::ResumeEnrollmentService do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  it 'resumes a paused enrollment with an active opt-in subscription and records audit' do
    enrollment = create(
      :aftercare_enrollment,
      account: account,
      created_by: administrator,
      status: :paused,
      paused_at: 10.minutes.ago
    )
    enrollment.create_aftercare_opt_in_subscription!(
      topic: enrollment.aftercare_sequence.opt_in_topic,
      provider: 'meta',
      capability_status: 'supported',
      status: :subscribed,
      token_ref: 'resume-token'
    )

    described_class.new(enrollment: enrollment, actor: administrator).perform

    expect(enrollment.reload.status).to eq('active')
    expect(enrollment.paused_at).to be_nil
    expect(
      enrollment.aftercare_audit_events.where(event_type: 'aftercare_enrollment_resumed').count
    ).to eq(1)
  end
end
