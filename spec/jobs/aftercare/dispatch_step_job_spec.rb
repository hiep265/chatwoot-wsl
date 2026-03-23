require 'rails_helper'

RSpec.describe Aftercare::DispatchStepJob, type: :job do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  it 'delegates step dispatch to the service' do
    enrollment = create(:aftercare_enrollment, account: account, created_by: administrator, status: :active)
    step = create(:aftercare_enrollment_step, aftercare_enrollment: enrollment, status: :scheduled)

    service = instance_double(Aftercare::DispatchStepService, perform: true)
    allow(Aftercare::DispatchStepService).to receive(:new).with(step: step).and_return(service)

    described_class.perform_now(step.id)

    expect(service).to have_received(:perform)
  end
end
