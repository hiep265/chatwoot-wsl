class Api::V1::Accounts::Aftercare::OptInEventsController < Api::V1::Accounts::Aftercare::BaseController
  def create
    subscription = AftercareOptInSubscription
                   .joins(:aftercare_enrollment)
                   .where(aftercare_enrollments: { account_id: Current.account.id })
                   .find(event_params[:subscription_id])

    result = Aftercare::OptInWebhookIngestService.new(
      subscription: subscription,
      event_name: event_params[:event_name],
      token_ref: event_params[:token_ref],
      occurred_at: event_params[:occurred_at],
      expires_at: event_params[:expires_at],
      payload: event_params[:payload]
    ).perform

    render json: {
      payload: {
        subscription_status: result[:subscription].status,
        enrollment_status: result[:enrollment].status
      }
    }, status: :ok
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def event_params
    params.permit(:subscription_id, :event_name, :token_ref, :occurred_at, :expires_at, payload: {})
  end
end
