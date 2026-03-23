require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Aftercare::SequencesController', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }

  describe 'GET /api/v1/accounts/:account_id/aftercare/sequences' do
    it 'returns active sequences with ordered steps' do
      sequence_code = "post_purchase_checkin_#{SecureRandom.hex(4)}"
      sequence = AftercareSequence.create!(
        code: sequence_code,
        name: 'Chăm sóc sau mua',
        opt_in_topic: "aftercare.#{sequence_code}",
        active: true
      )
      sequence.aftercare_sequence_steps.create!(
        position: 2,
        title: 'Nhắc triển khai',
        instructions: 'Nhắc khách triển khai',
        offset_minutes: 2880,
        enabled: true
      )
      sequence.aftercare_sequence_steps.create!(
        position: 1,
        title: 'Hỏi thăm',
        instructions: 'Hỏi khách sau mua',
        offset_minutes: 1440,
        enabled: true
      )

      get "/api/v1/accounts/#{account.id}/aftercare/sequences",
          headers: administrator.create_new_auth_token

      expect(response).to have_http_status(:success)
      body = JSON.parse(response.body, symbolize_names: true)
      matched_sequence = body[:payload].find { |item| item[:code] == sequence_code }

      expect(matched_sequence).to be_present
      expect(matched_sequence[:steps].map { |step| step[:position] }).to eq([1, 2])
    end
  end
end
