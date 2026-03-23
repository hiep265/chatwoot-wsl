require 'rails_helper'

RSpec.describe Webhooks::FacebookOptInJob do
  let(:payload) do
    {
      'sender' => { 'id' => 'contact-123' },
      'recipient' => { 'id' => 'page-456' },
      'timestamp' => Time.current.to_i,
      'optin' => {
        'type' => 'notification_messages',
        'payload' => { aftercare_subscription_id: 99 }.to_json
      }
    }
  end

  it 'parses the webhook payload and forwards it to the Meta opt-in processor' do
    service = instance_double(Aftercare::ProcessMetaOptInEventService, perform: true)

    expect(Aftercare::ProcessMetaOptInEventService)
      .to receive(:new)
      .with(payload: hash_including('recipient' => { 'id' => 'page-456' }))
      .and_return(service)

    described_class.perform_now(payload.to_json)

    expect(service).to have_received(:perform)
  end

  it 'unwraps the facebook-messenger gem messaging envelope before forwarding' do
    service = instance_double(Aftercare::ProcessMetaOptInEventService, perform: true)
    wrapped_payload = { 'messaging' => payload }

    expect(Aftercare::ProcessMetaOptInEventService)
      .to receive(:new)
      .with(payload: hash_including('recipient' => { 'id' => 'page-456' }))
      .and_return(service)

    described_class.perform_now(wrapped_payload.to_json)

    expect(service).to have_received(:perform)
  end
end
