class Api::BaseController < ApplicationController
  include AccessTokenAuthHelper
  respond_to :json
  before_action :authenticate_access_token!, if: :authenticate_by_access_token?
  before_action :validate_bot_access_token!, if: :authenticate_by_access_token?
  before_action :authenticate_user!, unless: :authenticate_by_access_token?

  private

  def authenticate_by_access_token?
    api_token = request.headers[:api_access_token]
    http_token = request.headers[:HTTP_API_ACCESS_TOKEN]
    Rails.logger.info("[Api::BaseController#authenticate_by_access_token?] api_access_token=#{api_token&.inspect}, HTTP_API_ACCESS_TOKEN=#{http_token&.inspect}")
    Rails.logger.info("[Api::BaseController#authenticate_by_access_token?] All headers: #{request.headers.env.select { |k, _| k.start_with?('HTTP_') || k == 'api_access_token' }.inspect}")
    has_token = api_token.present? || http_token.present?
    Rails.logger.info("[Api::BaseController#authenticate_by_access_token?] has_token=#{has_token}, controller=#{params[:controller]}, action=#{params[:action]}")
    has_token
  end

  def authenticate_user!
    Rails.logger.info("[Api::BaseController#authenticate_user!] Attempting user authentication")
    Rails.logger.info("[Api::BaseController#authenticate_user!] Headers: #{request.headers.env.select { |k, _| k.start_with?('HTTP_') }.inspect}")
    super
  rescue => e
    Rails.logger.error("[Api::BaseController#authenticate_user!] Error: #{e.class} - #{e.message}")
    raise
  end

  def check_authorization(model = nil)
    model ||= controller_name.classify.constantize

    authorize(model)
  end

  def check_admin_authorization?
    raise Pundit::NotAuthorizedError unless Current.account_user.administrator?
  end
end
