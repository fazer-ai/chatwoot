module Api::V1::Accounts::Concerns::WhatsappHealthManagement
  extend ActiveSupport::Concern

  included do
    skip_before_action :check_authorization, only: [:health, :register_webhook]
    before_action :check_admin_authorization?, only: [:register_webhook]
    before_action :validate_whatsapp_cloud_channel, only: [:health, :register_webhook]
  end

  def sync_templates
    return render status: :unprocessable_entity, json: { error: 'Template sync is only available for WhatsApp channels' } unless whatsapp_channel?

    trigger_template_sync
    render status: :ok, json: { message: 'Template sync initiated successfully' }
  rescue StandardError => e
    render status: :internal_server_error, json: { error: e.message }
  end

  def health
    health_data = Whatsapp::HealthService.new(@inbox.channel).fetch_health_status
    render json: health_data
  rescue StandardError => e
    Rails.logger.error "[INBOX HEALTH] Error fetching health data: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def submit_template
    # The WRITE path to Meta is gated behind its own installation_config flag (default OFF).
    # When off the endpoint is invisible (404, before any Meta call) so the write capability
    # is not leaked. The read-only template sync is intentionally NOT gated by this flag.
    return head :not_found unless whatsapp_template_submit_enabled?
    return render_not_whatsapp_cloud_error unless whatsapp_cloud_channel?

    result = Whatsapp::TemplateSubmitService.new(
      whatsapp_channel: @inbox.channel,
      template_payload: template_submit_params
    ).perform

    render json: { template_id: result[:template_id], status: result[:status] }, status: :created
  rescue CustomExceptions::Whatsapp::InvalidTemplate, CustomExceptions::Whatsapp::TemplateSubmissionError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def register_webhook
    Whatsapp::WebhookSetupService.new(@inbox.channel).register_callback

    render json: { message: 'Webhook registered successfully' }, status: :ok
  rescue StandardError => e
    Rails.logger.error "[INBOX WEBHOOK] Webhook registration failed: #{e.message}"
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def validate_whatsapp_cloud_channel
    return if @inbox.channel.is_a?(Channel::Whatsapp) && @inbox.channel.provider == 'whatsapp_cloud'

    render json: { error: 'Health data only available for WhatsApp Cloud API channels' }, status: :bad_request
  end

  def whatsapp_channel?
    @inbox.whatsapp? || (@inbox.twilio? && @inbox.channel.whatsapp?)
  end

  def whatsapp_cloud_channel?
    @inbox.channel.is_a?(Channel::Whatsapp) && @inbox.channel.provider == 'whatsapp_cloud'
  end

  def whatsapp_template_submit_enabled?
    ActiveModel::Type::Boolean.new.cast(GlobalConfigService.load('WHATSAPP_TEMPLATE_SUBMIT_ENABLED', false))
  end

  def render_not_whatsapp_cloud_error
    render json: { error: 'Template submission is only available for WhatsApp Cloud API channels' }, status: :unprocessable_entity
  end

  def template_submit_params
    template = params.require(:template)
    permitted = template.permit(:name, :language, :category).to_h
    # Meta's components schema is deeply variable (HEADER/BODY/FOOTER/BUTTONS with nested {{N}} samples).
    # Pass it through whole: it is only serialized and forwarded to Meta (no model/SQL sink), submit is admin-only.
    permitted['components'] = template[:components].as_json if template[:components].present?
    permitted
  end

  def trigger_template_sync
    if @inbox.whatsapp?
      Channels::Whatsapp::TemplatesSyncJob.perform_later(@inbox.channel)
    elsif @inbox.twilio? && @inbox.channel.whatsapp?
      Channels::Twilio::TemplatesSyncJob.perform_later(@inbox.channel)
    end
  end
end
