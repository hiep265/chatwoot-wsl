class AftercareMailer < ApplicationMailer
  helper_method :aftercare_sender_name

  def step_email(message)
    return unless smtp_config_set_or_development?

    @message = message
    @conversation = message.conversation
    @account = @conversation.account
    @contact = @conversation.contact
    @step = aftercare_step
    @step_title = @step&.title.to_s.strip.presence || 'Chăm sóc sau mua'
    @draft_body = @message.content.to_s.strip

    mail(
      to: @contact.email,
      from: aftercare_from_email,
      reply_to: aftercare_reply_to,
      subject: aftercare_subject
    ) do |format|
      format.text
      format.html
    end
  end

  private

  def aftercare_step
    step_id = @message.content_attributes&.dig('aftercare_step_id') ||
              @message.content_attributes&.dig(:aftercare_step_id)

    return if step_id.blank?

    AftercareEnrollmentStep.find_by(id: step_id)
  end

  def aftercare_subject
    @conversation.additional_attributes['mail_subject'].presence || "Chăm sóc sau mua: #{@step_title}"
  end

  def aftercare_sender_name
    'Chăm sóc khách hàng'
  end

  def aftercare_from_email
    "#{aftercare_sender_name} <#{sender_email_address}>"
  end

  def aftercare_reply_to
    sender_email_address
  end

  def sender_email_address
    configured_address = @account.support_email.presence ||
                         ENV.fetch('MAILER_SENDER_EMAIL', 'TA AI TECH <no-reply@taaitech.local>')

    Mail::Address.new(configured_address).address
  rescue Mail::Field::ParseError
    'no-reply@taaitech.local'
  end
end
