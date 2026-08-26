class Api::V1::Accounts::RedirectTokensController < Api::V1::Accounts::BaseController
  def create
    inbox = Current.account.inboxes.find(permitted_params[:inbox_id])
    authorize inbox, :show?
    return render(json: { error: 'not_a_web_widget' }, status: :unprocessable_entity) unless inbox.web_widget?

    payload = token_payload(inbox, origin_conversation)
    ttl = (permitted_params[:ttl_seconds].presence&.to_i || ::Widget::RedirectToken::DEFAULT_TTL).clamp(1, ::Widget::RedirectToken::DEFAULT_TTL)
    token = ::Widget::RedirectToken.generate(payload, ttl: ttl)

    render json: { token: token, expires_in: ttl, website_url: inbox.channel.website_url }
  end

  private

  # `origin_display_id` is the conversation the link is being sent ON (the WhatsApp entry thread).
  # It rides in the token because this is the only moment the two halves of a redirect episode are
  # known together: the resolve endpoint identifies the CONTACT, and a contact does not say which of
  # its conversations minted the link. Carried through to the widget conversation on resolve.
  def token_payload(inbox, origin)
    {
      inbox_id: inbox.id,
      identifier: permitted_params[:identifier],
      message: permitted_params[:message],
      origin_display_id: origin&.display_id
    }.compact.merge(identified_contact)
  end

  # WHICH CONTACT THIS LINK IS FOR, settled here because here is where it can be trusted.
  #
  # The resolve side had only the `identifier` to go on, and that is not enough to say whose identity
  # it is: the value is derived from a sequential contact id, so it is guessable, and it can move off
  # the contact between the mint and the click a day later. When it has moved,
  # `ContactIdentifyAction` finds nobody holding it and ASSIGNS it to the widget visitor instead of
  # merging onto the lead — which is how a lead ends up with two contacts, one of them squatting the
  # identifier of the other (fazer-ai/agents#286).
  #
  # This endpoint is account-authenticated, so the contact it resolves is a fact rather than a claim,
  # and it rides in the token, which is single-use, server-side and never seen by the widget.
  #
  # The key is written whenever an identifier is asked for, INCLUDING when nobody holds it — a nil
  # says "the mint looked and found none", which is a different answer from a token minted before
  # this existed, whose key is absent and which keeps the old behaviour for the day its TTL leaves it
  # live.
  def identified_contact
    identifier = permitted_params[:identifier].presence
    return {} if identifier.blank?

    { identified_contact_id: Current.account.contacts.find_by(identifier: identifier)&.id }
  end

  # The mint is the earliest shared entry point for the pairing, so the caller's right to name that
  # conversation is settled here rather than downstream. A display_id is account-wide and guessable,
  # and what the consumer does with the pairing is destructive — its follow-up ladder messages and
  # RESOLVES the conversation it names. An origin the caller cannot see is refused outright instead
  # of dropped: minting without it would silently hand back a link whose episode cannot be paired,
  # which is the failure this whole field exists to remove.
  def origin_conversation
    display_id = permitted_params[:origin_display_id].presence
    return if display_id.blank?

    conversation = Current.account.conversations.find_by!(display_id: display_id)
    authorize conversation, :show?
    conversation
  end

  def permitted_params
    params.permit(:inbox_id, :identifier, :message, :ttl_seconds, :origin_display_id)
  end
end
