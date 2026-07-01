class Webhooks::WhatsappController < ActionController::API
  include MetaTokenVerifyConcern

  before_action :verify_meta_signature!, only: :process_payload

  # Folga para o `SendReplyJob` (que persiste o `source_id` da mensagem
  # enviada) completar antes de o `messages.update` ser reprocessado. No
  # estado atual o SendReplyJob completa em ~200-500ms; 10 segundos é
  # margem generosa mesmo durante picos.
  MESSAGE_NOT_FOUND_RETRY_DELAY = 10.seconds

  def process_payload
    if inactive_whatsapp_number?
      Rails.logger.warn("Rejected webhook for inactive WhatsApp number: #{params[:phone_number]}")
      render json: { error: 'Inactive WhatsApp number' }, status: :unprocessable_entity
      return
    end

    perform_whatsapp_events_job
  end

  private

  def perform_whatsapp_events_job
    perform_sync if params[:awaitResponse].present?
    return if performed?

    Webhooks::WhatsappEventsJob.set(queue: target_queue).perform_later(params.to_unsafe_hash)
    head :ok
  end

  # Webhook payloads share a single job, but their priority depends on what
  # kind of event arrived. Splitting by queue prevents one class of event
  # from starving another during a spike — patient messages get the top
  # WhatsApp queue, status acks land in a dedicated mid-priority queue so
  # they keep flowing without elbowing messages out of the way, and the
  # rest (presence, account updates) stays on `:low`.
  #
  # Interactive Baileys events (QR pairing) jump straight to `:high`. They
  # are rare per session, sit at the same priority as `SendReplyJob`, and
  # — critically — they are NOT allowed to wait behind `presence.update`
  # backlog on `:low`. A backed-up `:low` was making QR pairings time out.
  def target_queue
    return :whatsapp_history if params[:importMode]
    return :high if interactive_baileys_event?
    return :whatsapp_messages if live_message_payload?
    return :whatsapp_statuses if status_only_payload?

    :low
  end

  # `connection.update` carries the QR data URL and the connection state
  # transitions (`connecting` → `open` / `close`). `creds.update` fires
  # once after the contact scans the QR, persisting credentials.
  def interactive_baileys_event?
    %w[connection.update creds.update].include?(params[:event].to_s)
  end

  # Detects whether the webhook is an actual inbound (or echo) WhatsApp
  # message. Covers the three providers we support:
  # - Baileys              -> top-level `event` field equals 'messages.upsert'
  # - WhatsApp Cloud (Meta) -> envelope object 'whatsapp_business_account'
  #                            with field 'messages' or 'smb_message_echoes'
  #                            AND a 'messages' / 'message_echoes' array in
  #                            the change value (NOT just statuses)
  # - Z-API                -> top-level `type` equals 'ReceivedCallback'
  def live_message_payload?
    baileys_message_payload? || cloud_message_payload? || zapi_message_payload?
  end

  def baileys_message_payload?
    params[:event].to_s == 'messages.upsert'
  end

  def cloud_message_payload?
    return false unless params[:object].to_s == 'whatsapp_business_account'

    field = params.dig(:entry, 0, :changes, 0, :field).to_s
    return false unless %w[messages smb_message_echoes].include?(field)

    # `field == 'messages'` covers BOTH real inbound messages and status
    # acks (sent / delivered / read). The discriminator is whether `value`
    # carries a `messages` array — without this check, every status ack
    # piled into :whatsapp_messages during peak hours and starved the
    # actual patient messages behind 1000s of cosmetic checkmark updates.
    value = params.dig(:entry, 0, :changes, 0, :value) || {}
    value[:messages].present? || value[:message_echoes].present?
  end

  def zapi_message_payload?
    params[:type].to_s == 'ReceivedCallback'
  end

  # WhatsApp Cloud status acks (sent / delivered / read). They share the
  # `field: messages` envelope with real messages, but their value carries
  # `statuses` instead of `messages`. Routed to their own queue so they
  # don't starve real messages but also don't sit at the bottom of `:low`.
  def status_only_payload?
    return false unless params[:object].to_s == 'whatsapp_business_account'

    field = params.dig(:entry, 0, :changes, 0, :field).to_s
    return false unless field == 'messages'

    value = params.dig(:entry, 0, :changes, 0, :value) || {}
    value[:statuses].present?
  end

  def perform_sync
    Webhooks::WhatsappEventsJob.perform_now(params.to_unsafe_hash)
  rescue Whatsapp::IncomingMessageBaileysService::InvalidWebhookVerifyToken
    head :unauthorized
  rescue Whatsapp::BaileysHandlers::MessagesUpdate::MessageNotFoundError
    # Race condition: `messages.update` chegou pelo caminho síncrono antes
    # do `SendReplyJob` ter persistido o `source_id` da mensagem original.
    # Reenfileiramos em background com folga e respondemos 200 para que o
    # Baileys não entre em loop de retry HTTP — o job re-enfileirado tem
    # `retry_on` configurado para a mesma exceção, então se o race persistir
    # o Sidekiq segue retentando com folga.
    Rails.logger.warn(
      '[whatsapp_webhook] MessageNotFoundError, re-enqueueing with delay ' \
      "phone=#{params[:phone_number]} event=#{params[:event]}"
    )
    Webhooks::WhatsappEventsJob.set(wait: MESSAGE_NOT_FOUND_RETRY_DELAY).perform_later(params.to_unsafe_hash)
    head :ok
  end

  def valid_token?(token)
    channel = Channel::Whatsapp.find_by(phone_number: params[:phone_number])
    whatsapp_webhook_verify_token = channel.provider_config['webhook_verify_token'] if channel.present?
    token == whatsapp_webhook_verify_token if whatsapp_webhook_verify_token.present?
  end

  def meta_app_secrets
    [
      *channel_meta_app_secrets(whatsapp_channel),
      GlobalConfigService.load('WHATSAPP_APP_SECRET', nil)
    ]
  end

  def whatsapp_channel
    @whatsapp_channel ||= whatsapp_business_payload_channel || Channel::Whatsapp.find_by(phone_number: params[:phone_number])
  end

  def meta_signature_verification_required?
    return true if whatsapp_channel.blank?
    return false unless whatsapp_channel.provider == 'whatsapp_cloud'
    return true if channel_meta_app_secrets(whatsapp_channel).present?

    whatsapp_channel.provider_config['source'] == 'embedded_signup'
  end

  def whatsapp_business_payload_channel
    return unless params[:object] == 'whatsapp_business_account'

    metadata = params.dig(:entry, 0, :changes, 0, :value, :metadata)
    return if metadata.blank?

    phone_number = normalized_phone_number(metadata[:display_phone_number])
    phone_number_id = metadata[:phone_number_id]
    channel = Channel::Whatsapp.find_by(phone_number: phone_number)

    return channel if channel && channel.provider_config['phone_number_id'] == phone_number_id
  end

  def normalized_phone_number(phone_number)
    return if phone_number.blank?

    phone_number = phone_number.to_s
    phone_number.start_with?('+') ? phone_number : "+#{phone_number}"
  end

  def inactive_whatsapp_number?
    phone_number = params[:phone_number]
    return false if phone_number.blank?

    inactive_numbers = GlobalConfig.get_value('INACTIVE_WHATSAPP_NUMBERS').to_s
    return false if inactive_numbers.blank?

    inactive_numbers_array = inactive_numbers.split(',').map(&:strip)
    inactive_numbers_array.include?(phone_number)
  end
end
