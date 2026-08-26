class Api::V1::Accounts::RedirectTokensController < Api::V1::Accounts::BaseController
  def create
    inbox = Current.account.inboxes.find(permitted_params[:inbox_id])
    authorize inbox, :show?
    return render(json: { error: 'not_a_web_widget' }, status: :unprocessable_entity) unless inbox.web_widget?

    payload = token_payload(inbox)
    ttl = (permitted_params[:ttl_seconds].presence&.to_i || ::Widget::RedirectToken::DEFAULT_TTL).clamp(1, ::Widget::RedirectToken::DEFAULT_TTL)
    token = ::Widget::RedirectToken.generate(payload, ttl: ttl)

    render json: { token: token, expires_in: ttl, website_url: inbox.channel.website_url }
  end

  private

  # `origin_display_id` is the conversation the link is being sent ON (the WhatsApp entry thread).
  # It rides in the token because this is the only moment the two halves of a redirect episode are
  # known together: the resolve endpoint identifies the CONTACT, and a contact does not say which of
  # its conversations minted the link. Carried through to the widget conversation on resolve.
  def token_payload(inbox)
    {
      inbox_id: inbox.id,
      identifier: permitted_params[:identifier],
      message: permitted_params[:message],
      origin_display_id: permitted_params[:origin_display_id].presence&.to_i
    }.compact
  end

  def permitted_params
    params.permit(:inbox_id, :identifier, :message, :ttl_seconds, :origin_display_id)
  end
end
