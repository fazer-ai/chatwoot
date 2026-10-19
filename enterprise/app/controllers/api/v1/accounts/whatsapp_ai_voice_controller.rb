# fazer.ai agents says whether its voice agent answers the calls of an inbox it is bound to, and
# the WebSocket their voice is streamed to. Sent again on every change on that side, so a fork
# that lost the URL is repaired by the next one.
class Api::V1::Accounts::WhatsappAiVoiceController < Api::V1::Accounts::BaseController
  STREAM_SCHEMES = %w[ws wss].freeze

  before_action :check_admin_authorization?
  before_action :set_channel, :ensure_enabled, :ensure_stream_url

  def update
    @channel.update_ai_voice!(enabled: enabled?, stream_url: stream_url)
    render json: { inbox_id: @channel.inbox.id, enabled: @channel.ai_voice_stream_url.present? }
  end

  private

  def set_channel
    @channel = Current.account.inboxes.find(params.require(:inbox_id)).channel
    return if @channel.is_a?(Channel::Whatsapp) && @channel.provider == 'native'

    render_unprocessable('Voice agents answer WhatsApp calls through the connector only')
  end

  def ensure_enabled
    render_unprocessable('enabled must be true or false') unless [true, false].include?(params[:enabled])
  end

  # A voice agent switched on needs somewhere to stream to, given now or kept from before.
  def ensure_stream_url
    return render_unprocessable('stream_url must be a ws:// or wss:// URL') if stream_url && !websocket_url?(stream_url)
    return unless enabled? && stream_url.nil? && @channel.provider_config.dig('ai_voice', 'stream_url').blank?

    render_unprocessable('stream_url is required to switch a voice agent on')
  end

  def enabled? = params[:enabled]

  def stream_url = params[:stream_url].presence

  def websocket_url?(value)
    uri = URI.parse(value)
    STREAM_SCHEMES.include?(uri.scheme) && uri.host.present?
  rescue URI::InvalidURIError
    false
  end

  def render_unprocessable(message)
    render json: { error: message }, status: :unprocessable_entity
  end
end
