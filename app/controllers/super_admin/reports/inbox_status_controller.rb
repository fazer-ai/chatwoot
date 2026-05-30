class SuperAdmin::Reports::InboxStatusController < SuperAdmin::ApplicationController
  # Window used to compute the "outgoing messages without a provider id"
  # rate per inbox. 24h matches the typical WhatsApp customer-service
  # window and gives operators a daily quality signal.
  OUTGOING_FAILURE_WINDOW = 24.hours

  def show; end

  def data
    inboxes = whatsapp_inboxes
    stats = compute_outgoing_failure_stats(inboxes)
    payload = inboxes.map { |inbox| serialize(inbox, stats[inbox.id]) }
    render json: { inboxes: payload, counts: count_states(payload) }
  end

  private

  # Lists every Channel::Whatsapp inbox across providers (baileys, zapi,
  # whatsapp_cloud, default/360dialog). Baileys + Z-API surface their
  # `provider_connection['connection']` socket state; the cloud-based
  # providers are stateless from our side (the Graph API is always
  # reachable, there is no QR pairing) so the report shows them as
  # permanently "connected".
  def whatsapp_inboxes
    # `inboxes.channel` is polymorphic so `includes(:channel)` raises
    # ActiveRecord::EagerLoadPolymorphicError. Resolve the channel ids
    # ourselves and preload `Channel::Whatsapp` records by hand. We also
    # eager-load accounts to avoid N+1 on `inbox.account.name`.
    inboxes = Inbox.joins(:account)
                   .joins('INNER JOIN channel_whatsapp ON channel_whatsapp.id = inboxes.channel_id')
                   .where(:channel_type => 'Channel::Whatsapp')
                   .includes(:account)
                   .order('accounts.name', 'inboxes.name')

    channels_by_id = Channel::Whatsapp.where(id: inboxes.map(&:channel_id)).index_by(&:id)
    inboxes.each { |inbox| inbox.association(:channel).target = channels_by_id[inbox.channel_id] }
    inboxes
  end

  # Providers whose connection state we read from the channel's
  # `provider_connection` JSONB (set by the Baileys / Z-API side
  # whenever a QR pairing or reconnect happens). Anything outside the
  # list is treated as permanently connected from the report's POV.
  SOCKET_PROVIDERS = %w[baileys zapi].freeze

  def serialize(inbox, stats)
    channel = inbox.channel
    provider = channel.provider.to_s
    socket_provider = SOCKET_PROVIDERS.include?(provider)
    connection_state = connection_state_for(channel, socket_provider)
    {
      inbox_id: inbox.id,
      inbox_name: inbox.name,
      account_id: inbox.account_id,
      account_name: inbox.account.name,
      phone_number: channel.phone_number,
      provider: provider,
      connection: connection_state,
      connected: connection_state == 'open',
      reconnect_supported: socket_provider,
      outgoing_24h_total: stats[:total],
      outgoing_24h_failed: stats[:failed]
    }
  end

  def connection_state_for(channel, socket_provider)
    return 'open' unless socket_provider

    channel.provider_connection.fetch('connection', 'close').presence || 'close'
  end

  # Single aggregate query for every inbox so we don't pay N round-trips
  # when the report fans out across hundreds of inboxes. A failure here is
  # an outgoing message with no provider id — both the legacy silent drop
  # (status defaulted to "sent") and the new explicit failed-status path
  # share this signal.
  def compute_outgoing_failure_stats(inboxes)
    default = Hash.new { |h, k| h[k] = { total: 0, failed: 0 } }
    return default if inboxes.empty?

    # `Message` has a default_scope ordering by `created_at`; combined with
    # GROUP BY that becomes an invalid SQL projection, so reorder('') first.
    rows = Message.reorder('')
                  .where(inbox_id: inboxes.map(&:id), message_type: :outgoing)
                  .where('created_at > ?', OUTGOING_FAILURE_WINDOW.ago)
                  .group(:inbox_id)
                  .pluck(
                    :inbox_id,
                    Arel.sql('COUNT(*)'),
                    Arel.sql('COUNT(*) FILTER (WHERE source_id IS NULL)')
                  )

    rows.each_with_object(default) do |(inbox_id, total, failed), acc|
      acc[inbox_id] = { total: total, failed: failed }
    end
  end

  def count_states(rows)
    rows.each_with_object(connected: 0, disconnected: 0) do |row, acc|
      row[:connected] ? acc[:connected] += 1 : acc[:disconnected] += 1
    end
  end
end
