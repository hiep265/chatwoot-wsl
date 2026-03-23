#######################################
# To create an external channel reply service
# - Inherit this as the base class.
# - Implement `channel_class` method in your child class.
# - Implement `perform_reply` method in your child class.
# - Implement additional custom logic for your `perform_reply` method.
# - When required override the validation_methods.
# - Use Childclass.new.perform.
######################################
class Base::SendOnChannelService
  pattr_initialize [:message!]

  def perform
    validate_target_channel
    return unless outgoing_message?
    return if invalid_message?
    return if aftercare_email_lane?

    perform_reply
  end

  private

  delegate :conversation, to: :message
  delegate :contact, :contact_inbox, :inbox, to: :conversation
  delegate :channel, to: :inbox

  def channel_class
    raise 'Overwrite this method in child class'
  end

  def perform_reply
    raise 'Overwrite this method in child class'
  end

  def outgoing_message_originated_from_channel?
    # TODO: we need to refactor this logic as more integrations comes by
    # chatwoot messages won't have source id at the moment
    # TODO: migrate source_ids to external_source_ids and check the source id relevant to specific channel
    message.source_id.present?
  end

  def outgoing_message?
    message.outgoing? || message.template?
  end

  def invalid_message?
    # private notes aren't send to the channels
    # we should also avoid the case of message loops, when outgoing messages are created from channel
    message.private? || outgoing_message_originated_from_channel?
  end

  def validate_target_channel
    raise 'Invalid channel service was called' if inbox.channel.class != channel_class
  end

  def normalized_content_attributes
    @normalized_content_attributes ||= begin
      attrs = message.content_attributes
      attrs = JSON.parse(attrs) if attrs.is_a?(String)
      attrs.is_a?(Hash) ? attrs.stringify_keys : {}
    rescue JSON::ParserError
      {}
    end
  end

  def aftercare_delivery_lane
    normalized_content_attributes['aftercare_delivery_lane'].to_s.presence
  end

  def aftercare_standard_lane?
    aftercare_delivery_lane == 'standard'
  end

  def aftercare_notification_messages_lane?
    aftercare_delivery_lane == 'notification_messages'
  end

  def aftercare_email_lane?
    aftercare_delivery_lane == 'gmail'
  end

  def aftercare_opt_in_subscription
    return @aftercare_opt_in_subscription if defined?(@aftercare_opt_in_subscription)

    subscription_id = normalized_content_attributes['aftercare_opt_in_subscription_id'].presence
    @aftercare_opt_in_subscription =
      subscription_id.present? ? AftercareOptInSubscription.find_by(id: subscription_id) : nil
  end

  def aftercare_notification_messages_token
    aftercare_opt_in_subscription&.token_ref
  end
end
