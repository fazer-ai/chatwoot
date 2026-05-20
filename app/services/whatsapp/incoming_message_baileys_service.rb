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

  # Window of inactivity (in seconds) after which the watchdog declares the
  # import complete. Baileys can fire `messaging-history.set` repeatedly for
  # the same pairing, so we can't rely on the per-firing `importBatch.index`
  # to detect the end. Once batches stop arriving for this long, we mark it
  # done.
  HISTORY_IMPORT_IDLE_WINDOW = 45.seconds

  private

  # Updates a running tally on the channel and schedules a watchdog job that
  # finalises the import once no new batches arrive for HISTORY_IMPORT_IDLE_WINDOW.
  # Each batch reschedules a fresh watchdog; the last surviving watchdog wins.
  def track_history_import_batch
    channel = inbox.channel
    return unless channel.respond_to?(:update_history_import_state!)

    channel.update_history_import_state!(next_history_import_state(channel))
    Channels::Whatsapp::BaileysHistoryImportFinalizeJob
      .set(wait: HISTORY_IMPORT_IDLE_WINDOW + 15.seconds)
      .perform_later(channel.id)
  rescue StandardError => e
    Rails.logger.error "Failed to track Baileys history import batch for inbox #{inbox.id}: #{e.message}"
  end

  def next_history_import_state(channel)
    counts = classify_history_batch_messages
    current_state = channel.history_import_state || {}
    now_iso = Time.current.iso8601

    # Status always reverts to 'in_progress' on a fresh batch: Baileys may
    # emit additional `messaging-history.set` events after a previous chunk
    # already had its watchdog flip the status to 'completed'.
    {
      status: 'in_progress',
      started_at: current_state['started_at'] || now_iso,
      last_batch_at: now_iso,
      processed_batches: current_state.fetch('processed_batches', 0) + 1,
      messages_imported: current_state.fetch('messages_imported', 0) + counts[:imported],
      messages_dropped_groups: current_state.fetch('messages_dropped_groups', 0) + counts[:dropped_groups],
      finished_at: nil
    }
  end

  # Splits the batch into two buckets based on `remoteJid` server suffix:
  # `@g.us` rows go to the dropped-groups bucket when group ingestion is off
  # (the default), everything else counts as imported. We classify on the
  # webhook payload (not on persisted messages) so the counters stay
  # consistent regardless of dedup, ignore_message? guards or stub handlers
  # — those produce noise we don't surface, and the UI just wants a clear
  # "X individuais / Y de grupos descartadas" breakdown.
  def classify_history_batch_messages
    messages = processed_params.dig(:data, :messages) || []
    return { imported: 0, dropped_groups: 0 } if messages.empty?

    groups_enabled = Whatsapp::Providers::WhatsappBaileysService.groups_enabled?
    imported = 0
    dropped_groups = 0

    messages.each do |msg|
      jid = msg.dig(:key, :remoteJid).to_s
      server = jid.split('@').last

      if server == 'g.us' && !groups_enabled
        dropped_groups += 1
      else
        imported += 1
      end
    end

    { imported: imported, dropped_groups: dropped_groups }
  end
end
