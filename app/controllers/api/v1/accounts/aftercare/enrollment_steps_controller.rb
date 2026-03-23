class Api::V1::Accounts::Aftercare::EnrollmentStepsController < Api::V1::Accounts::Aftercare::BaseController
  def update
    enrollment = scoped_enrollments.find(params[:enrollment_id])
    step = enrollment.aftercare_enrollment_steps.find(params[:id])

    Aftercare::UpdateStepDraftService.new(
      step: step,
      draft_body: update_params[:draft_body],
      actor: Current.user
    ).perform

    render json: { payload: step.reload.as_json_for_aftercare }, status: :ok
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue Aftercare::UpdateStepDraftService::InvalidDraftError => e
    render json: { error: 'Unable to update aftercare draft', detail: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: 'Unable to update aftercare draft', detail: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def regenerate_draft
    enrollment = scoped_enrollments.find(params[:enrollment_id])
    step = enrollment.aftercare_enrollment_steps.find(params[:id])

    Aftercare::GenerateStepDraftService.new(step: step, actor: Current.user).perform

    render json: { payload: step.reload.as_json_for_aftercare }, status: :ok
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue Aftercare::GenerateStepDraftService::DraftGenerationError => e
    render json: {
      error: 'Unable to regenerate aftercare draft',
      detail: e.message,
      payload: step&.reload&.as_json_for_aftercare
    }, status: :bad_gateway
  end

  def retry
    enrollment = scoped_enrollments.find(params[:enrollment_id])
    step = enrollment.aftercare_enrollment_steps.find(params[:id])

    Aftercare::RetryStepService.new(step: step, actor: Current.user).perform

    render json: { payload: step.reload.as_json_for_aftercare }, status: :ok
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue Aftercare::RetryStepService::RetryNotAllowedError => e
    render json: { error: 'Unable to retry aftercare step', detail: e.message }, status: :unprocessable_entity
  end

  private

  def scoped_enrollments
    AftercareEnrollment.where(account: Current.account)
  end

  def update_params
    params.permit(:draft_body)
  end
end
