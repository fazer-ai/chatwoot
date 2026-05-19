class Channels::Whatsapp::BaileysHistoryImportFinalizeJob < ApplicationJob
  # Belongs on the same low-priority queue as the import batches so it can
  # never starve live traffic.
  queue_as :whatsapp_history

  # Watchdog that flips the history-import status to `completed` once no new
  # `importMode: true` batches have landed for HISTORY_IMPORT_IDLE_WINDOW
  # seconds. Each batch enqueues a new instance; the last surviving job
  # finalises the import. Earlier jobs see a fresher `last_batch_at`
  # timestamp and no-op.
  def perform(channel_id)
    channel = Channel::Whatsapp.find_by(id: channel_id)
    return unless channel

    state = channel.history_import_state
    return if state.blank?
    return if state['status'] == 'completed'

    last_batch_at = parse_iso(state['last_batch_at'])
    return if last_batch_at.blank?
    return if Time.current - last_batch_at < Whatsapp::IncomingMessageBaileysService::HISTORY_IMPORT_IDLE_WINDOW

    channel.update_history_import_state!(
      status: 'completed',
      finished_at: Time.current.iso8601
    )
  end

  private

  def parse_iso(value)
    return if value.blank?

    Time.iso8601(value)
  rescue ArgumentError
    nil
  end
end
