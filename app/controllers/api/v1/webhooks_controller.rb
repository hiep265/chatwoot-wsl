class Api::V1::WebhooksController < ApplicationController
  skip_before_action :authenticate_user!, raise: false
  skip_before_action :set_current_user

  def twitter_crc
    render json: { response_token: "sha256=#{twitter_client.generate_crc(params[:crc_token])}" }
  end

  def twitter_events
    twitter_consumer.consume
    head :ok
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    head :ok
  end

  # Account-specific Twitter webhook endpoints
  def twitter_crc_for_account
    account = Account.find_by(id: params[:account_id])
    if account
      resolver = AccountSocialAppConfigResolver.new(account)
      consumer_secret = resolver.load('TWITTER_CONSUMER_SECRET', nil) || ENV.fetch('TWITTER_CONSUMER_SECRET', nil)
      client = Twitty::Facade.new do |config|
        config.consumer_secret = consumer_secret
      end
      render json: { response_token: "sha256=#{client.generate_crc(params[:crc_token])}" }
    else
      head :not_found
    end
  end

  def twitter_events_for_account
    twitter_consumer.consume
    head :ok
  rescue StandardError => e
    ChatwootExceptionTracker.new(e).capture_exception
    head :ok
  end

  private

  def twitter_client
    Twitty::Facade.new do |config|
      config.consumer_secret = ENV.fetch('TWITTER_CONSUMER_SECRET', nil)
    end
  end

  def twitter_consumer
    @twitter_consumer ||= ::Webhooks::Twitter.new(params)
  end
end
