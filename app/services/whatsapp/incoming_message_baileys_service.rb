class Whatsapp::IncomingMessageBaileysServic < Whatsapp::IncomingMessageBaseService
  def perform
    if params[:webhookVerifyToken] != whatsapp_channel.provider_config['webhook_verify_token']
      #NOTE: Can try log the requested IP address for further investigation
      Rails.logger.warn "Event with invalid webhook verify token for channel: #{channel.id}"
      head :unauthorized
    end
    return if params[:event].blank? || params[:data].blank?

    event_prefix = params[:event].split('.').first.underscore
    method_name = "process_#{event_prefix}"
    if respond_to?(method_name, true)
      send(method_name)
    else
      default_process_event
    end
  end

  private

  def process_connection
    return unless params[:event] == 'connection.update'

    data = params[:data]
    whatsapp_channel.update(provider_connection: data) if data[:connection].present?
    if data[:qrDataUrl].present?
      new_connection_data = whatsapp_channel.provider_connection || {}
      new_connection_data[:qrDataUrl] = data[:qrDataUrl]
      whatsapp_channel.update(provider_connection: new_connection_data)
    end
    Rails.logger.error "Bailey's connection error: #{data[:error]}" if data[:error].present?
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

  def process_messages
    return unless params[:event] == 'messages.upsert'

    process_messages
  end

  def default_process_event
    Rails.logger.warn "Bailey's unsupported event: #{params[:event]}"
  end
end
