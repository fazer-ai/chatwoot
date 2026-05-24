# Serves the WhatsApp simulator's HTML shell. It mirrors `WidgetsController`
# but only resolves `Channel::Simulator` (never a public WebWidget) and is
# always embedded from the dashboard's `/app/accounts/:id/simulator` page,
# so the iframe-ancestor allowlist is unconditional.
class SimulatorsController < ActionController::Base
  include WidgetHelper

  before_action :set_global_config
  before_action :set_web_widget
  before_action :ensure_account_is_active
  before_action :set_token
  before_action :set_contact
  before_action :build_contact
  after_action :allow_iframe_requests

  private

  def set_global_config
    @global_config = GlobalConfig.get(
      'LOGO_THUMBNAIL',
      'BRAND_NAME',
      'WIDGET_BRAND_URL',
      'DIRECT_UPLOADS_ENABLED',
      'MAXIMUM_FILE_UPLOAD_SIZE',
      'INSTALLATION_NAME'
    )
  end

  def set_web_widget
    @web_widget = ::Channel::Simulator.find_by!(website_token: permitted_params[:website_token])
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error('simulator channel does not exist')
    render json: { error: 'simulator channel does not exist' }, status: :not_found
  end

  def set_token
    @token = permitted_params[:cw_conversation]
    @auth_token_params = if @token.present?
                           ::Widget::TokenService.new(token: @token).decode_token
                         else
                           {}
                         end
  end

  def set_contact
    return if @auth_token_params[:source_id].nil?

    @contact_inbox = ::ContactInbox.find_by(
      inbox_id: @web_widget.inbox.id,
      source_id: @auth_token_params[:source_id]
    )

    @contact = @contact_inbox&.contact
  end

  def build_contact
    return if @contact.present?

    @contact_inbox, @token = build_contact_inbox_with_token(@web_widget, additional_attributes)
    @contact = @contact_inbox.contact
  end

  def ensure_account_is_active
    render json: { error: 'Account is suspended' }, status: :unauthorized unless @web_widget.inbox.account.active?
  end

  def additional_attributes
    if @web_widget.inbox.account.feature_enabled?('ip_lookup')
      { created_at_ip: request.remote_ip }
    else
      {}
    end
  end

  def permitted_params
    params.permit(:website_token, :cw_conversation)
  end

  # The simulator is always embedded inside the dashboard at
  # `/app/accounts/:id/simulator`, which is same-origin with the
  # Rails server. Drop X-Frame-Options and pin
  # `Content-Security-Policy: frame-ancestors 'self'` so any CSP
  # injected by an upstream proxy (nginx / Cloudflare) doesn't
  # block the same-origin iframe. The Devise-gated dashboard
  # route already restricts who reaches this URL.
  def allow_iframe_requests
    response.headers.delete('X-Frame-Options')
    response.headers['Content-Security-Policy'] = "frame-ancestors 'self'"
  end
end
