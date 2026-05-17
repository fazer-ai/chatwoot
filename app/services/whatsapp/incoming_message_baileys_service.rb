class Whatsapp::IncomingMessageBaileysService < Whatsapp::IncomingMessageBaseService
  include Events::Types
  include Whatsapp::BaileysHandlers::ConnectionUpdate
  include Whatsapp::BaileysHandlers::MessagesUpsert
  include Whatsapp::BaileysHandlers::MessagesUpdate
  include Whatsapp::BaileysHandlers::MessageReceiptUpdate
  include Whatsapp::BaileysHandlers::GroupParticipantsUpdate
  include Whatsapp::BaileysHandlers::GroupsUpdate
  include Whatsapp::BaileysHandlers::GroupsActivity
  include Whatsapp::BaileysHandlers::PresenceUpdate

  class InvalidWebhookVerifyToken < StandardError; end

  def perform # rubocop:disable Metrics/AbcSize
    raise InvalidWebhookVerifyToken if processed_params[:webhookVerifyToken] != inbox.channel.provider_config['webhook_verify_token']
    return if processed_params[:event].blank? || processed_params[:data].blank?

    # History-sync backfill: tag the thread-local so live-only side effects
    # (event dispatch, automation, notifications, outbound webhooks, read
    # receipts) bail out on messages that are days/weeks old.
    Current.history_import = processed_params[:importMode] == true
    if Current.history_import
      track_history_import_batch
    else
      Rails.configuration.dispatcher.dispatch(PROVIDER_EVENT_RECEIVED, Time.zone.now, inbox: inbox, event: processed_params[:event],
                                                                                      payload: processed_params[:data])
    end

    event_prefix = processed_params[:event].gsub(/[\.-]/, '_')
    method_name = "process_#{event_prefix}"
    if respond_to?(method_name, true)
      # TODO: Implement the methods for all expected events
      send(method_name)
    else
      Rails.logger.warn "Baileys unsupported event: #{processed_params[:event]}"
    end
  ensure
    Current.history_import = nil
  end

  private

  # Mirrors the `importBatch: { index, total, phase }` envelope the Baileys
  # node sends with each backfill chunk so the channel page can show progress
  # and we can mark the import done on the final batch.
  def track_history_import_batch
    channel = inbox.channel
    return unless channel.respond_to?(:update_history_import_state!)

    channel.update_history_import_state!(next_history_import_state(channel))
  rescue StandardError => e
    Rails.logger.error "Failed to track Baileys history import batch for inbox #{inbox.id}: #{e.message}"
  end

  def next_history_import_state(channel) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity
    batch = processed_params[:importBatch].is_a?(Hash) ? processed_params[:importBatch] : {}
    msgs_in_batch = processed_params.dig(:data, :messages)&.size || 0
    current_state = channel.history_import_state || {}
    total = batch[:total].to_i

    new_state = {
      status: 'in_progress',
      started_at: current_state['started_at'] || Time.current.iso8601,
      total_batches: total.positive? ? total : current_state['total_batches'],
      processed_batches: current_state.fetch('processed_batches', 0) + 1,
      messages_imported: current_state.fetch('messages_imported', 0) + msgs_in_batch
    }
    if last_history_import_batch?(batch, total)
      new_state[:status] = 'completed'
      new_state[:finished_at] = Time.current.iso8601
    end
    new_state
  end

  def last_history_import_batch?(batch, total)
    total.positive? && batch[:index].present? && batch[:index].to_i == total - 1
  end
end
