require 'rails_helper'

RSpec.describe Aftercare::GenerateStepDraftJob, type: :job do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  before do
    stub_request(:post, /graph.facebook.com/)
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
    allow(Facebook::Messenger::Subscriptions).to receive(:unsubscribe).and_return(true)
    GlobalConfig.clear_cache
  end

  describe '#perform' do
    it 'delegates draft generation for the enrollment step' do
      enrollment = create(:aftercare_enrollment, account: account, created_by: administrator)
      step = create(:aftercare_enrollment_step, aftercare_enrollment: enrollment)

      service = instance_double(Aftercare::GenerateStepDraftService, perform: true)
      allow(Aftercare::GenerateStepDraftService).to receive(:new).with(step: step, actor: enrollment.created_by).and_return(service)

      described_class.perform_now(step.id)

      expect(service).to have_received(:perform)
    end
  end
end
