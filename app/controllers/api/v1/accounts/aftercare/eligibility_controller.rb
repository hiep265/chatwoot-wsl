class Api::V1::Accounts::Aftercare::EligibilityController < Api::V1::Accounts::Aftercare::BaseController
  def show
    conversation = Current.account.conversations.find(params[:conversation_id])
    result = Aftercare::EligibilityService.new(conversation: conversation).perform

    render json: result.to_h, status: :ok
  end
end
