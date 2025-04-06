class Webhooks::WhatsappController < ActionController::API
  include MetaTokenVerifyConcern

  def process_payload
    if inactive_whatsapp_number?
      Rails.logger.warn("Rejected webhook for inactive WhatsApp number: #{params[:phone_number]}")
      render json: { error: 'Inactive WhatsApp number' }, status: :unprocessable_entity
      return
    end

    perform_webhook
  end

  def perform_webhook
    if params[:awaitResponse].present?
      begin
        Webhooks::WhatsappEventsJob.perform_now(params.to_unsafe_hash)
      rescue InvalidWebhookVerifyToken
        head :unauthorized and return
      rescue MessageNotFoundError
        head :not_found and return
      rescue StandardError => e
        Rails.logger.error("Error processing WhatsApp webhook: #{e.message}")
        head :bad_request and return
      end
    else
      Webhooks::WhatsappEventsJob.perform_later(params.to_unsafe_hash)
    end
    head :ok
  end

  private

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
