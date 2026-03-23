class AftercareListener < BaseListener
  def message_updated(event)
    message = extract_message_and_account(event)[0]

    Aftercare::SyncDispatchStatusService.new(
      message: message,
      previous_changes: event.data[:previous_changes]
    ).perform
  end
end
