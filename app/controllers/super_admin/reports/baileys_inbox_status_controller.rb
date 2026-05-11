class SuperAdmin::Reports::BaileysInboxStatusController < SuperAdmin::ApplicationController
  def show; end

  def data
    payload = baileys_inboxes.map { |inbox| serialize(inbox) }
    render json: { inboxes: payload, counts: count_states(payload) }
  end

  private

  def baileys_inboxes
    # `inboxes.channel` is polymorphic so `includes(:channel)` raises
    # ActiveRecord::EagerLoadPolymorphicError. Resolve the channel ids
    # ourselves and preload `Channel::Whatsapp` records by hand. We also
    # eager-load accounts to avoid N+1 on `inbox.account.name`.
    inboxes = Inbox.joins(:account)
                   .joins('INNER JOIN channel_whatsapp ON channel_whatsapp.id = inboxes.channel_id')
                   .where(:channel_type => 'Channel::Whatsapp', 'channel_whatsapp.provider' => 'baileys')
                   .includes(:account)
                   .order('accounts.name', 'inboxes.name')

    channels_by_id = Channel::Whatsapp.where(id: inboxes.map(&:channel_id)).index_by(&:id)
    inboxes.each { |inbox| inbox.association(:channel).target = channels_by_id[inbox.channel_id] }
    inboxes
  end

  def serialize(inbox)
    channel = inbox.channel
    connection_state = channel.provider_connection.fetch('connection', 'close').presence || 'close'
    {
      inbox_id: inbox.id,
      inbox_name: inbox.name,
      account_id: inbox.account_id,
      account_name: inbox.account.name,
      phone_number: channel.phone_number,
      connection: connection_state,
      connected: connection_state == 'open'
    }
  end

  def count_states(rows)
    rows.each_with_object(connected: 0, disconnected: 0) do |row, acc|
      row[:connected] ? acc[:connected] += 1 : acc[:disconnected] += 1
    end
  end
end
