require 'rails_helper'
require 'net/http'
require 'json'
require 'mail'

RSpec.describe 'Aftercare local Gmail flow', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:chatbotlevan_base_url) { ENV.fetch('CHATBOTLEVAN_BASE_URL', '').to_s.strip.chomp('/') }

  around do |example|
    skip 'Set LOCAL_AFTERCARE_E2E=1 to run the local chatbotlevan E2E flow' unless ENV['LOCAL_AFTERCARE_E2E'] == '1'
    raise 'CHATBOTLEVAN_BASE_URL must be configured for LOCAL_AFTERCARE_E2E' if chatbotlevan_base_url.blank?

    WebMock.allow_net_connect!

    begin
      health_response = Net::HTTP.get_response(URI("#{chatbotlevan_base_url}/health"))
      raise "chatbotlevan healthcheck failed with status #{health_response.code}" unless health_response.code.to_i == 200

      original_delivery_method = ActionMailer::Base.delivery_method
      original_smtp_settings = ActionMailer::Base.smtp_settings.dup

      with_modified_env(
        'SMTP_ADDRESS' => 'chatwoot-mailhog-1',
        'SMTP_PORT' => '1025',
        'SMTP_DOMAIN' => 'mailhog.local',
        'SMTP_ENABLE_STARTTLS_AUTO' => 'false',
        'SMTP_SSL' => 'false',
        'SMTP_TLS' => 'false'
      ) do
        ActionMailer::Base.delivery_method = :smtp
        ActionMailer::Base.smtp_settings = {
          address: 'chatwoot-mailhog-1',
          port: 1025,
          domain: 'mailhog.local',
          enable_starttls_auto: false,
          ssl: false,
          tls: false,
          open_timeout: 5,
          read_timeout: 5
        }

        clear_mailhog_messages!
        example.run
      ensure
        clear_mailhog_messages!
        ActionMailer::Base.delivery_method = original_delivery_method
        ActionMailer::Base.smtp_settings = original_smtp_settings
      end
    ensure
      WebMock.disable_net_connect!(allow_localhost: true)
    end
  end

  before do
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
    allow(Facebook::Messenger::Subscriptions).to receive(:unsubscribe).and_return(true)
    allow(Aftercare::GmailDeliveryCapability).to receive(:smtp_ready?).and_return(true)
    GlobalConfig.clear_cache
    clear_enqueued_jobs
    clear_performed_jobs
  end

  it 'creates an enrollment via the API, drafts with local chatbotlevan, and sends Gmail after the 24h window' do
    facebook_channel = create(:channel_facebook_page, account: account)
    inbox = create(:inbox, account: account, channel: facebook_channel)
    conversation = create(:conversation, account: account, inbox: inbox)
    conversation.contact.update!(name: 'Lan E2E', email: 'lan.aftercare.e2e@example.com')

    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      content: 'Em vừa mua gói cơ bản xong.',
      created_at: 30.minutes.ago
    )
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :outgoing,
      content: 'Cảm ơn bạn đã đăng ký. Mình sẽ hỗ trợ nếu bạn cần nhé.',
      created_at: 25.minutes.ago
    )
    create(
      :message,
      account: account,
      inbox: inbox,
      conversation: conversation,
      message_type: :incoming,
      content: 'Bên mình dùng như thế nào vậy?',
      created_at: 20.minutes.ago
    )

    sequence_code = "local_gmail_e2e_#{SecureRandom.hex(4)}"
    sequence = AftercareSequence.create!(
      code: sequence_code,
      name: 'Chăm sóc sau mua local E2E',
      opt_in_topic: "aftercare.#{sequence_code}",
      active: true
    )
    sequence.aftercare_sequence_steps.create!(
      position: 1,
      title: 'Hỏi thăm ngày 2',
      instructions: 'Hỏi khách đã bắt đầu triển khai chưa và có cần hỗ trợ gì thêm không.',
      offset_minutes: 1_560,
      enabled: true
    )

    perform_enqueued_jobs do
      post "/api/v1/accounts/#{account.id}/aftercare/enrollments",
           headers: administrator.create_new_auth_token,
           params: {
             conversation_id: conversation.id,
             sequence_id: sequence.id,
             staff_note: 'Khách vừa mua gói cơ bản, cần follow-up nhẹ nhàng.',
             timezone_name: 'Asia/Bangkok',
             anchor_at: Time.current.iso8601,
             steps: [
               {
                 position: 1,
                 scheduled_for: 26.hours.from_now.iso8601,
                 enabled: true,
                 step_note: 'Ưu tiên hỏi thăm tiến độ triển khai thật nhẹ nhàng.'
               }
             ]
           }
    end

    expect(response).to have_http_status(:created)

    enrollment = AftercareEnrollment.order(:id).last
    step = enrollment.aftercare_enrollment_steps.first.reload
    subscription = enrollment.aftercare_opt_in_subscription.reload

    expect(enrollment.status).to eq('active')
    expect(subscription.provider).to eq('gmail')
    expect(subscription.status).to eq('subscribed')
    expect(step.draft_status).to eq('ready')
    expect(step.draft_body.to_s.strip).to be_present
    expect(step.draft_version.to_s.strip).to be_present
    expect(step.draft_input_snapshot).to be_present
    expect(step.draft_input_snapshot['recent_messages'].length).to eq(3)

    expect(mailhog_messages.fetch('count')).to eq(0)

    travel_to(2.days.from_now) do
      expect do
        perform_enqueued_jobs do
          Aftercare::ProcessDueStepsJob.perform_now
        end
      end.to change { conversation.messages.outgoing.count }.by(1)
        .and change { mailhog_messages.fetch('count') }.by(1)
    end

    step.reload
    enrollment.reload

    dispatch_log = step.aftercare_dispatch_logs.order(:id).last
    outgoing_message = dispatch_log.message.reload
    delivered_email = mailhog_messages.fetch('items').last
    parsed_email = Mail.read_from_string(delivered_email.dig('Raw', 'Data'))
    decoded_email_body = parsed_email.body.decoded.force_encoding(Encoding::UTF_8).scrub
    normalized_email_body = normalize_line_endings(decoded_email_body)
    normalized_step_draft_body = normalize_line_endings(step.draft_body)
    delivered_message_id = delivered_email.dig('Content', 'Headers', 'Message-ID')&.first.to_s.delete_prefix('<').delete_suffix('>')

    expect(step.status).to eq('sent')
    expect(enrollment.status).to eq('completed')
    expect(dispatch_log.provider).to eq('gmail')
    expect(dispatch_log.status).to eq('sent')
    expect(dispatch_log.provider_message_id).to eq(outgoing_message.source_id)
    expect(dispatch_log.metadata).to include(
      'delivery_lane' => 'gmail',
      'dispatch_reason' => 'outside_standard_window_with_gmail_ready',
      'delivery_email' => 'lan.aftercare.e2e@example.com'
    )
    expect(outgoing_message.content_attributes).to include(
      'aftercare_delivery_lane' => 'gmail',
      'aftercare_delivery_email' => 'lan.aftercare.e2e@example.com'
    )
    expect(outgoing_message.content).to eq(step.draft_body)
    expect(outgoing_message.source_id.to_s).to be_present
    expect(delivered_email.dig('Content', 'Headers', 'To').join(',')).to include('lan.aftercare.e2e@example.com')
    expect(normalized_email_body).to include(normalized_step_draft_body)
    expect(outgoing_message.source_id).to eq(delivered_message_id)
  end

  def normalize_line_endings(value)
    value.to_s.gsub(/\r\n?/, "\n")
  end

  def clear_mailhog_messages!
    uri = URI('http://chatwoot-mailhog-1:8025/api/v1/messages')
    request = Net::HTTP::Delete.new(uri)

    Net::HTTP.start(uri.host, uri.port) do |http|
      http.request(request)
    end
  end

  def mailhog_messages
    uri = URI('http://chatwoot-mailhog-1:8025/api/v2/messages')
    response = Net::HTTP.get_response(uri)
    raise "MailHog API failed with status #{response.code}" unless response.code.to_i == 200

    JSON.parse(response.body)
  end
end
