class Conversations::UpdateMessageStatusJob < ApplicationJob
  queue_as :deferred

  # This job only support marking messages as read or delivered, update this array if we want to support more statuses
  VALID_STATUSES = %w[read delivered].freeze

  def perform(conversation_id, timestamp, status = :read)
    return unless VALID_STATUSES.include?(status.to_s)

    conversation = Conversation.find_by(id: conversation_id)

    return unless conversation

    # Only real customer-facing outbound messages participate in delivery/read updates.
    conversation.messages.where(status: %w[sent delivered])
                .where(message_type: %w[outgoing template])
                .where('messages.created_at <= ?', timestamp).find_each do |message|
      Messages::StatusUpdateService.new(message, status).perform
    end
  end
end
