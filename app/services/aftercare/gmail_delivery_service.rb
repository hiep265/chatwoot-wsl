module Aftercare
  class GmailDeliveryService
    def initialize(message:)
      @message = message
    end

    def perform
      raise ArgumentError, 'Aftercare Gmail delivery requires a contact email' if contact_email.blank?

      reply_mail = ConversationReplyMailer.with(account: @message.account).email_reply(@message).deliver_now
      return if reply_mail.blank?

      @message.update!(source_id: reply_mail.message_id)
    rescue StandardError => e
      ChatwootExceptionTracker.new(e, account: @message.account).capture_exception
      Messages::StatusUpdateService.new(@message, 'failed', e.message).perform
    end

    private

    def contact_email
      @message.conversation.contact.email.to_s.strip.presence
    end
  end
end
