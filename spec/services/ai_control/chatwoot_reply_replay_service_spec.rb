# frozen_string_literal: true

require 'rails_helper'

RSpec.describe AiControl::ChatwootReplyReplayService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, status: :open) }
  let(:config_key) { "ai_control:chatwoot_reply_replay:config:#{account.id}" }
  let(:state_key) do
    "ai_control:chatwoot_reply_replay:last_attempt:#{account.id}:#{conversation.reload.display_id}"
  end
  let(:service) { described_class.new }

  after do
    ::Redis::Alfred.delete(config_key)
    ::Redis::Alfred.delete(state_key)
  end

  describe '#perform' do
    it 'replays the latest incoming public message for enabled accounts with overdue unanswered conversations' do
      ::Redis::Alfred.set(config_key, { enabled: true }.to_json)

      incoming_message = nil
      travel_to(Time.zone.parse('2026-04-23 10:00:00 UTC')) do
        incoming_message = create(
          :message,
          account: account,
          inbox: inbox,
          conversation: conversation,
          message_type: 'incoming',
          private: false,
          content: 'Can you help me?',
          created_at: 2.hours.ago
        )
        conversation.update_columns(
          waiting_since: 2.hours.ago,
          last_activity_at: 2.hours.ago,
          status: Conversation.statuses[:open]
        )

        with_modified_env(
          'CHATBOTLEVAN_INTERNAL_BASE_URL' => '',
          'CHATBOTLEVAN_BASE_URL' => 'https://chatbotlevan.test'
        ) do
          expect(WebhookJob).to receive(:perform_later).with(
            'https://chatbotlevan.test/webhooks/chatwoot/messages',
            hash_including(
              event: 'message_created',
              id: incoming_message.id,
              content: incoming_message.webhook_data[:content]
            )
          ).once

          expect(service.perform).to eq(1)

          replay_state = JSON.parse(::Redis::Alfred.get(state_key))
          expect(replay_state['message_id']).to eq(incoming_message.id)
          expect(replay_state['conversation_id']).to eq(conversation.display_id)
          expect(replay_state['attempted_at']).to be_present
        end
      end
    end

    it 'does not replay again within 60 minutes for the same waiting customer message' do
      ::Redis::Alfred.set(config_key, { enabled: true }.to_json)

      incoming_message = nil
      travel_to(Time.zone.parse('2026-04-23 10:00:00 UTC')) do
        incoming_message = create(
          :message,
          account: account,
          inbox: inbox,
          conversation: conversation,
          message_type: 'incoming',
          private: false,
          content: 'Still waiting',
          created_at: 3.hours.ago
        )
        conversation.update_columns(
          waiting_since: 3.hours.ago,
          last_activity_at: 3.hours.ago,
          status: Conversation.statuses[:open]
        )
        ::Redis::Alfred.set(
          state_key,
          {
            message_id: incoming_message.id,
            conversation_id: conversation.display_id,
            attempted_at: 30.minutes.ago.iso8601
          }.to_json
        )

        with_modified_env(
          'CHATBOTLEVAN_INTERNAL_BASE_URL' => '',
          'CHATBOTLEVAN_BASE_URL' => 'https://chatbotlevan.test'
        ) do
          expect(WebhookJob).not_to receive(:perform_later)
          expect(service.perform).to eq(0)
        end
      end
    end

    it 'skips conversations outside the 24 hour active window even if still unanswered' do
      ::Redis::Alfred.set(config_key, { enabled: true }.to_json)

      travel_to(Time.zone.parse('2026-04-23 10:00:00 UTC')) do
        create(
          :message,
          account: account,
          inbox: inbox,
          conversation: conversation,
          message_type: 'incoming',
          private: false,
          content: 'Old unanswered message',
          created_at: 26.hours.ago
        )
        conversation.update_columns(
          waiting_since: 26.hours.ago,
          last_activity_at: 26.hours.ago,
          status: Conversation.statuses[:open]
        )

        with_modified_env(
          'CHATBOTLEVAN_INTERNAL_BASE_URL' => '',
          'CHATBOTLEVAN_BASE_URL' => 'https://chatbotlevan.test'
        ) do
          expect(WebhookJob).not_to receive(:perform_later)
          expect(service.perform).to eq(0)
        end
      end
    end

    it 'replays a recent unanswered incoming message when waiting_since is stale from an older turn' do
      ::Redis::Alfred.set(config_key, { enabled: true }.to_json)

      incoming_message = nil
      travel_to(Time.zone.parse('2026-04-23 10:00:00 UTC')) do
        create(
          :message,
          account: account,
          inbox: inbox,
          conversation: conversation,
          message_type: 'incoming',
          private: false,
          content: 'Old customer message',
          created_at: 5.days.ago
        )
        incoming_message = create(
          :message,
          account: account,
          inbox: inbox,
          conversation: conversation,
          message_type: 'incoming',
          private: false,
          content: 'Recent unanswered message',
          created_at: 2.hours.ago
        )
        conversation.update_columns(
          waiting_since: 5.days.ago,
          last_activity_at: 2.hours.ago,
          status: Conversation.statuses[:open]
        )

        with_modified_env(
          'CHATBOTLEVAN_INTERNAL_BASE_URL' => '',
          'CHATBOTLEVAN_BASE_URL' => 'https://chatbotlevan.test'
        ) do
          expect(WebhookJob).to receive(:perform_later).with(
            'https://chatbotlevan.test/webhooks/chatwoot/messages',
            hash_including(
              event: 'message_created',
              id: incoming_message.id,
              content: incoming_message.webhook_data[:content]
            )
          ).once

          expect(service.perform).to eq(1)
        end
      end
    end

    it 'skips conversations labeled for AI handoff or pause' do
      ::Redis::Alfred.set(config_key, { enabled: true }.to_json)

      travel_to(Time.zone.parse('2026-04-23 10:00:00 UTC')) do
        %w[ai_handoff ai_paused].each do |label|
          labeled_conversation = create(:conversation, account: account, inbox: inbox, status: :open)
          create(
            :message,
            account: account,
            inbox: inbox,
            conversation: labeled_conversation,
            message_type: 'incoming',
            private: false,
            content: "Waiting with #{label}",
            created_at: 2.hours.ago
          )
          labeled_conversation.update_columns(
            waiting_since: 2.hours.ago,
            last_activity_at: 2.hours.ago,
            status: Conversation.statuses[:open]
          )
          labeled_conversation.update_labels([label])
        end

        with_modified_env(
          'CHATBOTLEVAN_INTERNAL_BASE_URL' => '',
          'CHATBOTLEVAN_BASE_URL' => 'https://chatbotlevan.test'
        ) do
          expect(WebhookJob).not_to receive(:perform_later)
          expect(service.perform).to eq(0)
        end
      end
    end

    it 'skips conversations that have a public outgoing reply after the waiting customer message' do
      ::Redis::Alfred.set(config_key, { enabled: true }.to_json)

      travel_to(Time.zone.parse('2026-04-23 10:00:00 UTC')) do
        create(
          :message,
          account: account,
          inbox: inbox,
          conversation: conversation,
          message_type: 'incoming',
          private: false,
          content: 'Need support',
          created_at: 2.hours.ago
        )
        conversation.update_columns(
          waiting_since: 2.hours.ago,
          status: Conversation.statuses[:open]
        )
        platform_reply = build(
          :message,
          account: account,
          inbox: inbox,
          conversation: conversation,
          message_type: 'outgoing',
          private: false,
          source_id: 'platform_reply_123',
          content: 'An agent already replied',
          created_at: 1.hour.ago
        )
        platform_reply.sender = nil
        platform_reply.save!

        with_modified_env(
          'CHATBOTLEVAN_INTERNAL_BASE_URL' => '',
          'CHATBOTLEVAN_BASE_URL' => 'https://chatbotlevan.test'
        ) do
          expect(WebhookJob).not_to receive(:perform_later)
          expect(service.perform).to eq(0)
        end
      end
    end
  end
end
