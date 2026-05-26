class Webhooks::WhatsappController < ActionController::API
  include MetaTokenVerifyConcern

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
  # kind of event arrived. Status / presence / account updates would otherwise
  # share `:low` with the actual patient messages and starve them during a
  # spike — splitting by queue prevents that without dropping any event.
  def target_queue
    return :whatsapp_history if params[:importMode]
    return :whatsapp_messages if live_message_payload?

    :low
  end

  # Detects whether the webhook is an actual inbound (or echo) WhatsApp
  # message. Covers the three providers we support:
  # - Baileys              -> top-level `event` field equals 'messages.upsert'
  # - WhatsApp Cloud (Meta) -> envelope object 'whatsapp_business_account'
  #                            with field 'messages' or 'smb_message_echoes'
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
    %w[messages smb_message_echoes].include?(field)
  end

  def zapi_message_payload?
    params[:type].to_s == 'ReceivedCallback'
  end

  def perform_sync
    Webhooks::WhatsappEventsJob.perform_now(params.to_unsafe_hash)
  rescue Whatsapp::IncomingMessageBaileysService::InvalidWebhookVerifyToken
    head :unauthorized
  rescue Whatsapp::IncomingMessageBaileysService::MessageNotFoundError
    head :not_found
  end

  def valid_token?(token)
    channel = Channel::Whatsapp.find_by(phone_number: params[:phone_number])
    whatsapp_webhook_verify_token = channel.provider_config['webhook_verify_token'] if channel.present?
    token == whatsapp_webhook_verify_token if whatsapp_webhook_verify_token.present?
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
