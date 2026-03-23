class Api::V1::Accounts::Aftercare::EnrollmentsController < Api::V1::Accounts::Aftercare::BaseController
  def index
    enrollments = AftercareEnrollment
                  .where(account: Current.account)
                  .includes(:contact, :conversation, :aftercare_sequence, :aftercare_enrollment_steps, :aftercare_opt_in_subscription)
                  .recent_first

    render json: { payload: enrollments.map(&:as_json_for_aftercare) }, status: :ok
  end

  def show
    enrollment = scoped_enrollments.find(params[:id])
    render json: { payload: enrollment.as_json_for_aftercare }, status: :ok
  end

  def create
    conversation = resolve_create_conversation!(create_params[:conversation_id])
    sequence = AftercareSequence.for_account(Current.account).active.find(create_params[:sequence_id])

    enrollment = Aftercare::CreateEnrollmentService.new(
      account: Current.account,
      conversation: conversation,
      sequence: sequence,
      created_by: Current.user,
      params: create_params.to_h
    ).perform

    render json: { payload: enrollment.reload.as_json_for_aftercare }, status: :created
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue Aftercare::CreateEnrollmentService::IneligibleError => e
    render json: { error: 'Conversation is not eligible for aftercare enrollment', detail: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: 'Unable to create aftercare enrollment', detail: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def cancel
    enrollment = scoped_enrollments.find(params[:id])
    Aftercare::CancelEnrollmentService.new(enrollment: enrollment, actor: Current.user).perform

    render json: { payload: enrollment.reload.as_json_for_aftercare }, status: :ok
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: 'Unable to cancel aftercare enrollment', detail: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def pause
    enrollment = scoped_enrollments.find(params[:id])
    Aftercare::PauseEnrollmentService.new(enrollment: enrollment, actor: Current.user).perform

    render json: { payload: enrollment.reload.as_json_for_aftercare }, status: :ok
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue Aftercare::PauseEnrollmentService::PauseNotAllowedError => e
    render json: { error: 'Unable to pause aftercare enrollment', detail: e.message }, status: :unprocessable_entity
  end

  def resume
    enrollment = scoped_enrollments.find(params[:id])
    Aftercare::ResumeEnrollmentService.new(enrollment: enrollment, actor: Current.user).perform

    render json: { payload: enrollment.reload.as_json_for_aftercare }, status: :ok
  rescue ActiveRecord::RecordNotFound => e
    render json: { error: e.message }, status: :not_found
  rescue Aftercare::ResumeEnrollmentService::ResumeNotAllowedError => e
    render json: { error: 'Unable to resume aftercare enrollment', detail: e.message }, status: :unprocessable_entity
  end

  private

  def scoped_enrollments
    AftercareEnrollment
      .where(account: Current.account)
      .includes(:contact, :conversation, :aftercare_sequence, :aftercare_enrollment_steps, :aftercare_opt_in_subscription)
  end

  def create_params
    params.permit(
      :conversation_id,
      :sequence_id,
      :contact_email,
      :staff_note,
      :timezone_name,
      :anchor_at,
      steps: [:position, :scheduled_for, :offset_minutes, :enabled, :step_note, :title, :instructions]
    )
  end

  def resolve_create_conversation!(raw_conversation_id)
    resolved_id = raw_conversation_id.to_s.strip
    conversation = Current.account.conversations.find_by(id: resolved_id)
    conversation ||= Current.account.conversations.find_by(display_id: resolved_id)
    return conversation if conversation.present?

    raise ActiveRecord::RecordNotFound, "Couldn't find Conversation with 'id'=#{resolved_id} [WHERE \"conversations\".\"account_id\" = #{Current.account.id}]"
  end
end
