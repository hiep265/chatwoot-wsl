require 'rails_helper'

RSpec.describe Captain::Tools::HandoffTool, type: :model do
  let(:account) { create(:account) }
  let(:assistant) { create(:captain_assistant, account: account) }
  let(:tool) { described_class.new(assistant) }
  let(:user) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }
  let(:tool_context) { Struct.new(:state).new({ conversation: { id: conversation.id } }) }

  describe '#description' do
    it 'returns the correct description' do
      expect(tool.description).to eq('Hand off the conversation to a human agent when unable to assist further')
    end
  end

  describe '#parameters' do
    it 'returns the correct parameters' do
      expect(tool.parameters).to have_key(:reason)
      expect(tool.parameters).to have_key(:is_lead)
      expect(tool.parameters).to have_key(:customer_request)
      expect(tool.parameters).to have_key(:is_urgent)
      expect(tool.parameters).to have_key(:is_upset)
      expect(tool.parameters).to have_key(:pause_bot)

      expect(tool.parameters[:reason].name).to eq(:reason)
      expect(tool.parameters[:reason].type).to eq('string')
      expect(tool.parameters[:reason].description).to eq('The reason why handoff is needed (optional)')
      expect(tool.parameters[:reason].required).to be false

      expect(tool.parameters[:is_lead].type).to eq('string')
      expect(tool.parameters[:is_lead].required).to be false

      expect(tool.parameters[:customer_request].type).to eq('string')
      expect(tool.parameters[:customer_request].required).to be false

      expect(tool.parameters[:is_urgent].type).to eq('string')
      expect(tool.parameters[:is_urgent].required).to be false

      expect(tool.parameters[:is_upset].type).to eq('string')
      expect(tool.parameters[:is_upset].required).to be false

      expect(tool.parameters[:pause_bot].type).to eq('string')
      expect(tool.parameters[:pause_bot].required).to be false
    end
  end

  describe '#perform' do
    context 'when conversation exists' do
      context 'with reason provided' do
        it 'creates a private note with reason and hands off conversation' do
          reason = 'Customer needs specialized support'

          expect do
            result = tool.perform(tool_context, reason: reason)
            expect(result).to eq("Conversation handed off to human support team (Reason: #{reason})")
          end.to change(Message, :count).by(1)
        end

        it 'creates message with correct attributes' do
          reason = 'Customer needs specialized support'
          tool.perform(tool_context, reason: reason)

          created_message = Message.last
          expect(created_message.content).to eq(reason)
          expect(created_message.message_type).to eq('outgoing')
          expect(created_message.private).to be true
          expect(created_message.sender).to eq(assistant)
          expect(created_message.account).to eq(account)
          expect(created_message.inbox).to eq(inbox)
          expect(created_message.conversation).to eq(conversation)
        end

        it 'triggers bot handoff on conversation' do
          # The tool finds the conversation by ID, so we need to mock the found conversation
          found_conversation = Conversation.find(conversation.id)
          scoped_conversations = Conversation.where(account_id: assistant.account_id)
          allow(Conversation).to receive(:where).with(account_id: assistant.account_id).and_return(scoped_conversations)
          allow(scoped_conversations).to receive(:find_by).with(id: conversation.id).and_return(found_conversation)
          expect(found_conversation).to receive(:bot_handoff!)

          tool.perform(tool_context, reason: 'Test reason')
        end

        it 'logs tool usage with reason' do
          reason = 'Customer needs help'
          expect(tool).to receive(:log_tool_usage).with(
            'tool_handoff',
            { conversation_id: conversation.id, reason: reason }
          )

          tool.perform(tool_context, reason: reason)
        end
      end

      context 'without reason provided' do
        it 'creates a private note with default content and hands off conversation' do
          expect do
            result = tool.perform(tool_context)
            expect(result).to eq('Conversation handed off to human support team')
          end.to change(Message, :count).by(1)

          created_message = Message.last
          expect(created_message.content).to eq('Agent requested handoff')
        end

        it 'logs tool usage with default reason' do
          expect(tool).to receive(:log_tool_usage).with(
            'tool_handoff',
            { conversation_id: conversation.id, reason: 'Agent requested handoff' }
          )

          tool.perform(tool_context)
        end
      end

      context 'with handoff metadata provided' do
        it 'persists metadata to custom_attributes, applies labels, and sets urgent priority' do
          tool.perform(
            tool_context,
            reason: 'Need human support',
            is_lead: 'true',
            customer_request: 'Pricing and demo',
            is_urgent: 'true',
            is_upset: 'false',
            pause_bot: 'true'
          )

          conversation.reload

          handoff_attrs = conversation.custom_attributes.dig('captain', 'handoff')
          expect(handoff_attrs).to be_a(Hash)
          expect(handoff_attrs['reason']).to eq('Need human support')
          expect(handoff_attrs['customer_request']).to eq('Pricing and demo')
          expect(handoff_attrs['is_lead']).to eq(true)
          expect(handoff_attrs['is_urgent']).to eq(true)
          expect(handoff_attrs['is_upset']).to eq(false)
          expect(handoff_attrs['pause_bot']).to eq(true)

          expect(conversation.label_list).to include('ai_handoff')
          expect(conversation.label_list).to include('ai_lead')
          expect(conversation.label_list).to include('ai_urgent')
          # Không còn dùng ai_paused - chỉ dùng ai_handoff để đánh dấu

          expect(conversation.priority).to eq('urgent')
        end
      end

      context 'when handoff fails' do
        before do
          # Mock the conversation lookup and handoff failure
          found_conversation = Conversation.find(conversation.id)
          scoped_conversations = Conversation.where(account_id: assistant.account_id)
          allow(Conversation).to receive(:where).with(account_id: assistant.account_id).and_return(scoped_conversations)
          allow(scoped_conversations).to receive(:find_by).with(id: conversation.id).and_return(found_conversation)
          allow(found_conversation).to receive(:bot_handoff!).and_raise(StandardError, 'Handoff error')

          exception_tracker = instance_double(ChatwootExceptionTracker)
          allow(ChatwootExceptionTracker).to receive(:new).and_return(exception_tracker)
          allow(exception_tracker).to receive(:capture_exception)
        end

        it 'returns error message' do
          result = tool.perform(tool_context, reason: 'Test')
          expect(result).to eq('Failed to handoff conversation')
        end

        it 'captures exception' do
          exception_tracker = instance_double(ChatwootExceptionTracker)
          expect(ChatwootExceptionTracker).to receive(:new).with(instance_of(StandardError)).and_return(exception_tracker)
          expect(exception_tracker).to receive(:capture_exception)

          tool.perform(tool_context, reason: 'Test')
        end
      end
    end

    context 'when conversation does not exist' do
      let(:tool_context) { Struct.new(:state).new({ conversation: { id: 999_999 } }) }

      it 'returns error message' do
        result = tool.perform(tool_context, reason: 'Test')
        expect(result).to eq('Conversation not found')
      end

      it 'does not create a message' do
        expect do
          tool.perform(tool_context, reason: 'Test')
        end.not_to change(Message, :count)
      end
    end

    context 'when conversation state is missing' do
      let(:tool_context) { Struct.new(:state).new({}) }

      it 'returns error message' do
        result = tool.perform(tool_context, reason: 'Test')
        expect(result).to eq('Conversation not found')
      end
    end

    context 'when conversation id is nil' do
      let(:tool_context) { Struct.new(:state).new({ conversation: { id: nil } }) }

      it 'returns error message' do
        result = tool.perform(tool_context, reason: 'Test')
        expect(result).to eq('Conversation not found')
      end
    end
  end

  describe '#active?' do
    it 'returns true for public tools' do
      expect(tool.active?).to be true
    end
  end

  describe 'out of office message after handoff' do
    context 'when outside business hours' do
      before do
        inbox.update!(
          working_hours_enabled: true,
          out_of_office_message: 'We are currently closed. Please leave your email.'
        )
        inbox.working_hours.find_by(day_of_week: Time.current.in_time_zone(inbox.timezone).wday).update!(
          closed_all_day: true,
          open_all_day: false
        )
      end

      it 'sends out of office message after handoff' do
        expect do
          tool.perform(tool_context, reason: 'Customer needs help')
        end.to change { conversation.messages.template.count }.by(1)

        ooo_message = conversation.messages.template.last
        expect(ooo_message.content).to eq('We are currently closed. Please leave your email.')
      end
    end

    context 'when within business hours' do
      before do
        inbox.update!(
          working_hours_enabled: true,
          out_of_office_message: 'We are currently closed.'
        )
        inbox.working_hours.find_by(day_of_week: Time.current.in_time_zone(inbox.timezone).wday).update!(
          open_all_day: true,
          closed_all_day: false
        )
      end

      it 'does not send out of office message after handoff' do
        expect do
          tool.perform(tool_context, reason: 'Customer needs help')
        end.not_to(change { conversation.messages.template.count })
      end
    end

    context 'when no out of office message is configured' do
      before do
        inbox.update!(
          working_hours_enabled: true,
          out_of_office_message: nil
        )
        inbox.working_hours.find_by(day_of_week: Time.current.in_time_zone(inbox.timezone).wday).update!(
          closed_all_day: true,
          open_all_day: false
        )
      end

      it 'does not send out of office message' do
        expect do
          tool.perform(tool_context, reason: 'Customer needs help')
        end.not_to(change { conversation.messages.template.count })
      end
    end
  end
end
