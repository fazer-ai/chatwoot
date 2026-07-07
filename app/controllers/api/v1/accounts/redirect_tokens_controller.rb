class Api::V1::Accounts::RedirectTokensController < Api::V1::Accounts::BaseController
  def create
    inbox = Current.account.inboxes.find(permitted_params[:inbox_id])
    authorize inbox, :show?
    return render(json: { error: 'not_a_web_widget' }, status: :unprocessable_entity) unless inbox.web_widget?

    payload = { inbox_id: inbox.id, identifier: permitted_params[:identifier], message: permitted_params[:message] }.compact
    ttl = (permitted_params[:ttl_seconds].presence&.to_i || ::Widget::RedirectToken::DEFAULT_TTL).clamp(1, ::Widget::RedirectToken::DEFAULT_TTL)
    token = ::Widget::RedirectToken.generate(payload, ttl: ttl)

    render json: { token: token, expires_in: ttl, website_url: inbox.channel.website_url }
  end

  private

  def permitted_params
    params.permit(:inbox_id, :identifier, :message, :ttl_seconds)
  end
end
