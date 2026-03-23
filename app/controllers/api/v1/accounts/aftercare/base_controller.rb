class Api::V1::Accounts::Aftercare::BaseController < Api::V1::Accounts::BaseController
  before_action :authorize_account_update

  private

  def authorize_account_update
    authorize Current.account, :update?
  end
end
