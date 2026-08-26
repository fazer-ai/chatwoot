class Api::V1::Widget::RedirectTokensController < Api::V1::Widget::BaseController
  include WidgetHelper

  def create
    payload = ::Widget::RedirectToken.consume(permitted_params[:token])
    return render(json: { error: 'invalid_token' }, status: :not_found) if payload.blank?
    return render(json: { error: 'invalid_token' }, status: :not_found) if payload['inbox_id'] != @web_widget.inbox.id

    identify_from_token(payload)
    resume_or_start_conversation(payload)
    record_redirect_origin(payload)

    render json: {
      widget_auth_token: @widget_auth_token,
      conversation_id: @conversation&.display_id
    }
  end

  private

  def identify_from_token(payload)
    if payload['identifier'].present? && @contact.identifier.present? && @contact.identifier != payload['identifier']
      @contact_inbox, @widget_auth_token = build_contact_inbox_with_token(@web_widget)
      @contact = @contact_inbox.contact
    end
    @contact_inbox.update!(hmac_verified: true)
    return if payload['identifier'].blank?

    @contact = ContactIdentifyAction.new(
      contact: @contact,
      params: { identifier: payload['identifier'] },
      discard_invalid_attrs: true
    ).perform
  end

  def resume_or_start_conversation(payload)
    if payload['message'].present?
      @conversation = conversations.where.not(status: :resolved).last || start_conversation
      inject_cloned_message(payload['message'])
    else
      @conversation = conversations.last || start_conversation
    end
  end

  # The pairing, written at the one moment it is a fact rather than an inference. Everything this
  # side knows afterwards is about the CONTACT, and a contact carries neither the conversation the
  # link was minted on nor which of its threads the lead came from — five different predicates over
  # the mirrored rows were tried downstream and each is wrong in its own way (fazer-ai/agents#222).
  #
  # Last write wins: a token is burned by exactly one click, so the value is always the origin of the
  # redirect that just happened, which is the episode the follow-up ladder acts on. A re-entry with
  # no origin in the token leaves the previous one standing rather than clearing it.
  def record_redirect_origin(payload)
    origin = payload['origin_display_id']
    return if origin.blank? || @conversation.blank?
    return if @conversation.redirect_origin_display_id == origin

    @conversation.update!(redirect_origin_display_id: origin)
  end

  def start_conversation
    ::Conversation.create!(
      account_id: @web_widget.inbox.account_id,
      inbox_id: @web_widget.inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id
    )
  end

  def inject_cloned_message(content)
    @conversation.messages.create!(
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      sender: @contact,
      content: content,
      message_type: :incoming
    )
  end

  def permitted_params
    params.permit(:website_token, :token)
  end
end
