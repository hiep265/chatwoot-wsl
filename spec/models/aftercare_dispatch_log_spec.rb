require 'rails_helper'

RSpec.describe AftercareDispatchLog, type: :model do
  let(:account) { create(:account) }
  let(:sequence) { create(:aftercare_sequence, account: account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:enrollment) do
    create(
      :aftercare_enrollment,
      account: account,
      aftercare_sequence: sequence,
      created_by: administrator
    )
  end
  let(:step) { create(:aftercare_enrollment_step, aftercare_enrollment: enrollment) }

  it 'requires enrollment, step, attempt_key, and status' do
    log = described_class.new

    expect(log).not_to be_valid
    expect(log.errors[:aftercare_enrollment]).to be_present
    expect(log.errors[:aftercare_enrollment_step]).to be_present
    expect(log.errors[:attempt_key]).to be_present
    expect(log.errors[:status]).to be_present
  end

  it 'defaults provider to meta' do
    log = described_class.new

    log.validate

    expect(log.provider).to eq('meta')
  end

  it 'enforces uniqueness of attempt_key per step' do
    described_class.create!(
      aftercare_enrollment: enrollment,
      aftercare_enrollment_step: step,
      attempt_key: 'aftercare:step:1',
      status: 'sent',
      provider: 'meta'
    )

    duplicate = described_class.new(
      aftercare_enrollment: enrollment,
      aftercare_enrollment_step: step,
      attempt_key: 'aftercare:step:1',
      status: 'failed',
      provider: 'meta'
    )

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:attempt_key]).to be_present
  end
end
