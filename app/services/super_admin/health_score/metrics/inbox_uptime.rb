# V1 simplification: point-in-time snapshot of whether the account's worst
# WhatsApp inbox is currently connected. For socket-based providers
# (Baileys / Z-API) reads `provider_connection['connection']`; for
# Cloud-based providers (whatsapp_cloud, default/360dialog) treats as
# always connected (the Graph API has no QR pairing on our side).
#
# V1.5 will swap this for a true rolling 7d uptime once we have a sampler
# job feeding `inbox_connection_samples`.
class SuperAdmin::HealthScore::Metrics::InboxUptime < SuperAdmin::HealthScore::Metrics::Base
  SOCKET_PROVIDERS = %w[baileys zapi].freeze

  def compute
    channels = whatsapp_channels
    return missing(:no_whatsapp_inboxes) if channels.empty?

    states = channels.map { |channel| [channel.phone_number, connection_open?(channel)] }
    all_disconnected = states.none? { |(_, open)| open }
    worst_pct = states.map { |(_, open)| open ? 1.0 : 0.0 }.min
    sub_score = (worst_pct * 100).round

    present(
      sub_score,
      worst_inbox_pct: worst_pct,
      inboxes_count: channels.size,
      all_disconnected: all_disconnected,
      inboxes: states.map { |(phone, open)| { phone_number: phone, connected: open } }
    )
  end

  private

  def whatsapp_channels
    inbox_ids = account.inboxes.where(channel_type: 'Channel::Whatsapp').pluck(:channel_id)
    return [] if inbox_ids.empty?

    Channel::Whatsapp.where(id: inbox_ids).to_a
  end

  def connection_open?(channel)
    return true unless SOCKET_PROVIDERS.include?(channel.provider.to_s)

    (channel.provider_connection || {}).fetch('connection', 'close') == 'open'
  end
end
