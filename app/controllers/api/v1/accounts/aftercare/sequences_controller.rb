class Api::V1::Accounts::Aftercare::SequencesController < Api::V1::Accounts::Aftercare::BaseController
  def index
    sequences = AftercareSequence.for_account(Current.account).active.ordered.includes(:aftercare_sequence_steps)
    render json: { payload: sequences.map(&:as_json_for_aftercare) }, status: :ok
  end
end
