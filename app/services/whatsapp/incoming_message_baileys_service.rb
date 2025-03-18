class Whatsapp::IncomingMessageBaileysService < Whatsapp::IncomingMessageBaseService
  class InvalidWebhookVerifyToken < StandardError; end

  def perform
    raise InvalidWebhookVerifyToken if processed_params[:webhookVerifyToken] != whatsapp_channel.provider_config['webhook_verify_token']
    return if processed_params[:event].blank? || processed_params[:data].blank?

    event_prefix = processed_params[:event].gsub(/[\.-]/, '_')
    method_name = "process_#{event_prefix}"
    if respond_to?(method_name, true)
      send(method_name)
    else
      Rails.logger.warn "Bailey's unsupported event: #{processed_params[:event]}"
    end
  end

  private

  def process_connection_update
    updated_connection = processed_params[:data].slice(:connection, :qrDataUrl, :error)
    updated_connection.transform_keys! { |key| key.underscore.to_sym }
    whatsapp_channel.provider_connection.merge!(updated_connection)

    Rails.logger.error "Bailey's connection error: #{data[:error]}" if data[:error].present?

    whatsapp_channel.save!
  end

  def process_credentials_update; end
  def process_messaging_history; end
  def process_chats; end
  def process_presence; end
  def process_contacts; end
  def process_message_receipt; end
  def process_groups; end
  def process_blocklist; end
  def process_call; end
  def process_group_participants; end
  def process_label; end

  def process_messages_upsert
    process_messages
  end
end
