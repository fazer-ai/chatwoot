# Endpoints used by the super-admin "Inbox status" report to drive the
# link-device modal (setup / disconnect / poll status) without going
# through the tenant-scoped /api/v1/accounts/:id/inboxes/:id/* routes —
# super-admin doesn't carry an account context. The route name stays
# `baileys_connection` for backward compatibility, but the controller
# accepts any socket-paired WhatsApp provider (Baileys + Z-API) since
# `channel.setup_channel_provider` already dispatches on
# `channel.provider_service`.
class SuperAdmin::Inboxes::BaileysConnectionsController < SuperAdmin::ApplicationController
  SOCKET_PROVIDERS = %w[baileys zapi].freeze

  before_action :fetch_socket_inbox

  def show
    render json: serialize_state
  end

  def create
    @inbox.channel.setup_channel_provider
    render json: serialize_state
  rescue StandardError => e
    Rails.logger.error "[SUPER_ADMIN][INBOX_CONNECT] setup failed for inbox #{@inbox.id}: #{e.class}: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @inbox.channel.disconnect_channel_provider
    render json: serialize_state
  rescue StandardError => e
    Rails.logger.error "[SUPER_ADMIN][INBOX_CONNECT] disconnect failed for inbox #{@inbox.id}: #{e.class}: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  ensure
    @inbox.channel.update_provider_connection!(connection: 'close') if @inbox&.channel.respond_to?(:update_provider_connection!)
  end

  private

  def fetch_socket_inbox
    @inbox = Inbox.joins(
      'INNER JOIN channel_whatsapp ON channel_whatsapp.id = inboxes.channel_id'
    ).where(
      :channel_type => 'Channel::Whatsapp',
      'channel_whatsapp.provider' => SOCKET_PROVIDERS
    ).find(params[:inbox_id])
  end

  def serialize_state
    pc = @inbox.channel.provider_connection || {}
    {
      inbox_id: @inbox.id,
      connection: pc['connection'].presence || 'close',
      qr_data_url: pc['qr_data_url'],
      error: pc['error']
    }
  end
end
