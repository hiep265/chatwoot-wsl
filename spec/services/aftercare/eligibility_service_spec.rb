require 'rails_helper'

RSpec.describe Aftercare::EligibilityService do
  before do
    stub_request(:post, /graph.facebook.com/)
    allow(Facebook::Messenger::Subscriptions).to receive(:subscribe).and_return(true)
    allow(Facebook::Messenger::Subscriptions).to receive(:unsubscribe).and_return(true)
    GlobalConfig.clear_cache
  end

  describe '#perform' do
    it 'returns blocked_outside_window for stale messenger conversations' do
      facebook_channel = create(:channel_facebook_page)
      inbox = create(:inbox, account: facebook_channel.account, channel: facebook_channel)
      conversation = create(:conversation, account: facebook_channel.account, inbox: inbox)
      create(:message, account: conversation.account, inbox: inbox, conversation: conversation, created_at: 2.days.ago)

      result = described_class.new(conversation: conversation).perform

      expect(result.eligible).to be(false)
      expect(result.reason_code).to eq('outside_messaging_window')
      expect(result.channel_key).to eq('messenger')
    end

    it 'still uses a strict 24-hour window even when the human agent extension is enabled' do
      facebook_channel = create(:channel_facebook_page)
      inbox = create(:inbox, account: facebook_channel.account, channel: facebook_channel)
      conversation = create(:conversation, account: facebook_channel.account, inbox: inbox)
      create(
        :message,
        account: conversation.account,
        inbox: inbox,
        conversation: conversation,
        created_at: 2.days.ago
      )

      allow(GlobalConfigService).to receive(:load).and_call_original
      allow(GlobalConfigService)
        .to receive(:load)
        .with('ENABLE_MESSENGER_CHANNEL_HUMAN_AGENT', anything)
        .and_return(true)

      result = described_class.new(conversation: conversation).perform

      expect(result.eligible).to be(false)
      expect(result.reason_code).to eq('outside_messaging_window')
      expect(result.window_expires_at).to be_within(5.seconds).of(
        conversation.messages.incoming.last.created_at + 24.hours
      )
    end

    it 'allows recent instagram conversations even when the human agent extension is disabled' do
      instagram_channel = create(:channel_instagram)
      inbox = instagram_channel.inbox
      conversation = create(:conversation, account: instagram_channel.account, inbox: inbox)
      config = InstallationConfig.find_or_initialize_by(name: 'ENABLE_INSTAGRAM_CHANNEL_HUMAN_AGENT')
      config.value = false
      config.locked = false
      config.save!
      GlobalConfig.clear_cache
      create(
        :message,
        account: conversation.account,
        inbox: inbox,
        conversation: conversation,
        created_at: 2.hours.ago
      )

      result = described_class.new(conversation: conversation).perform

      expect(result.eligible).to be(true)
      expect(result.reason_code).to eq('eligible')
      expect(result.channel_key).to eq('instagram')
      expect(result.capability_status).to eq('supported')
      expect(result.window_expires_at).to be_within(5.seconds).of(
        conversation.messages.incoming.last.created_at + 24.hours
      )
    end
  end
end
