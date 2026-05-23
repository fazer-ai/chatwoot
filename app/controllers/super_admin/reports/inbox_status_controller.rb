class SuperAdmin::Reports::InboxStatusController < SuperAdmin::ApplicationController
  def show; end

  def data
    payload = whatsapp_inboxes.map { |inbox| serialize(inbox) }
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

  def serialize(inbox)
    channel = inbox.channel
    provider = channel.provider.to_s
    socket_provider = SOCKET_PROVIDERS.include?(provider)
    connection_state = if socket_provider
                         channel.provider_connection.fetch('connection', 'close').presence || 'close'
                       else
                         'open'
                       end
    {
      inbox_id: inbox.id,
      inbox_name: inbox.name,
      account_id: inbox.account_id,
      account_name: inbox.account.name,
      phone_number: channel.phone_number,
      provider: provider,
      connection: connection_state,
      connected: connection_state == 'open',
      reconnect_supported: socket_provider
    }
  end

  def count_states(rows)
    rows.each_with_object(connected: 0, disconnected: 0) do |row, acc|
      row[:connected] ? acc[:connected] += 1 : acc[:disconnected] += 1
    end
  end
end
