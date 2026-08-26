class Api::V1::Widget::RedirectTokensController < Api::V1::Widget::BaseController
  include WidgetHelper

  def create
    payload = ::Widget::RedirectToken.consume(permitted_params[:token])
    return render(json: { error: 'invalid_token' }, status: :not_found) if payload.blank?
    return render(json: { error: 'invalid_token' }, status: :not_found) if payload['inbox_id'] != @web_widget.inbox.id

    identify_from_token(payload)
    resume_or_start_conversation(payload)

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

  # The order here is load-bearing. AgentBotListener is on the SYNC dispatcher, so the payload a
  # consumer receives for the cloned message is built INSIDE Message.create!, from the conversation as
  # it stands at that moment. The pairing therefore has to be on the row before the message exists, or
  # the message — the event a consumer actually acts on — carries the PREVIOUS episode's origin.
  #
  # Measured on a running instance, mint + resolve over HTTP with an agent bot on the widget inbox:
  #
  #   origin changes, cloned message   ->  1. conversation_updated (new origin)
  #                                        2. message_created      (new origin)
  #   origin changes, no message       ->  1. conversation_updated (new origin)
  #   origin unchanged, cloned message ->  1. message_created      (new origin)
  #   origin unchanged, no message     ->  nothing
  #
  # So the update PRECEDES the message rather than following it, and that is the point: every event a
  # consumer can see already names the right origin. The standalone update is not a second trigger —
  # it states a value, and a consumer that acts on episodes acts on the customer message, which is the
  # only thing either path produces that is one.
  def resume_or_start_conversation(payload)
    if payload['message'].present?
      @conversation = conversations.where.not(status: :resolved).last || start_conversation(payload)
      with_episode_lock do
        record_redirect_origin(payload)
        inject_cloned_message(payload['message'])
      end
    else
      @conversation = conversations.last || start_conversation(payload)
      with_episode_lock { record_redirect_origin(payload) }
    end
  end

  # The pairing and the message it belongs to, under ONE lock, because the invariant above is about
  # the two TOGETHER: the message's payload is built from the conversation as it stands when
  # Message.create! runs, so the pairing has to still be this request's when it does. Two
  # message-bearing redirects resuming the same conversation at once break that if the lock ends with
  # the origin write — A writes 77 and releases, B writes 91 and finishes, then A's message goes out
  # naming 77 while the row says 91, and a consumer mirroring that message disagrees with Chatwoot
  # about which WhatsApp thread this episode has. Held across both, the two requests serialize whole:
  # whichever commits last owns the row AND sent the last message, and they name the same origin.
  #
  # A conversation born in this request is not locked. start_conversation already wrote the origin
  # from the same payload, nothing could have raced a row that did not exist, and a just-created
  # Conversation still carries an unpersisted `display_id` change that `with_lock` refuses to lock
  # over ("Locking a record with unpersisted changes is not supported").
  def with_episode_lock(&)
    return yield if @conversation.blank? || @conversation.previously_new_record?

    @conversation.with_lock(&)
  end

  # The pairing, written at the one moment it is a fact rather than an inference. Everything this
  # side knows afterwards is about the CONTACT, and a contact carries neither the conversation the
  # link was minted on nor which of its threads the lead came from — five different predicates over
  # the mirrored rows were tried downstream and each is wrong in its own way (fazer-ai/agents#222).
  #
  # Last write wins: a token is burned by exactly one click, so the value is always the origin of the
  # redirect that just happened, which is the episode the follow-up ladder acts on.
  #
  # A token that names NO origin clears it, rather than leaving the previous one standing. Consuming a
  # token is the one event that sets this column, so a re-entry that cannot say where it came from
  # leaves the stored answer with nothing behind it — the lead came back through a link this instance
  # cannot attribute. Keeping it would hand a consumer that MESSAGES and RESOLVES the named
  # conversation full confidence in a previous episode's answer; clearing it sends that consumer to
  # whatever it does with no answer at all, which is a decision it makes knowingly.
  #
  # Note the asymmetry with the consumer's own /reset, which deliberately KEEPS the pairing
  # (fazer-ai/agents#355): a reset is not a redirect and does not un-click the link, so the stored
  # answer is still the last true one. Here a redirect did happen and did not name an origin.
  #
  # On the message-less path this update is the ONLY thing that happens, so it has to be observable on
  # its own — nothing is created and no message is sent. That is why the column is in
  # Conversation#list_of_keys: the update then emits its own conversation_updated, carrying the new
  # pairing and a fresh `updated_at` for consumers to order it by.
  # The equality check is write avoidance and nothing more: ActiveRecord records no change for a write
  # of the same value, so `previous_changes` comes back empty and notify_conversation_updation returns
  # before dispatching anything. Removing this line leaves every event this endpoint emits identical
  # and only adds an UPDATE per repeated click — measured, because a repeated link from ONE WhatsApp
  # conversation is a supported flow and it would be easy to read the silence as this guard's doing.
  # `.presence` normalizes for the equality check below and nothing else: an integer column casts ''
  # to nil on assignment (measured), so a malformed token writes nil either way — but `nil == ''` is
  # false, so without it the guard would miss and spend an UPDATE that changes nothing. That is why
  # deleting it leaves the specs green.
  #
  # But it has to compare against the ROW, not against an instance loaded before the token was even
  # resolved, and the lock its caller holds is what makes those the same thing: `with_lock` reloads
  # under SELECT ... FOR UPDATE, so the comparison sees whatever a concurrent resume committed and
  # this request's own token still gets the last word. Take that lock away and the window does not
  # merely re-open — a stale instance holding this request's own origin makes the guard skip, and
  # skipping is silent on both counts: no write, and no conversation_updated for the message-less
  # path. Dropping the guard instead does not help either, because ActiveRecord issues no UPDATE for
  # a value the instance already believes it has. The staleness is the defect; the guard only reads
  # it out.
  def record_redirect_origin(payload)
    return if @conversation.blank?

    origin = payload['origin_display_id'].presence
    return if @conversation.redirect_origin_display_id == origin

    @conversation.update!(redirect_origin_display_id: origin)
  end

  # A brand-new conversation carries the pairing from birth, so even the conversation_created event
  # names its origin — the same reason record_redirect_origin runs before the message on the resume
  # path.
  def start_conversation(payload)
    ::Conversation.create!(
      account_id: @web_widget.inbox.account_id,
      inbox_id: @web_widget.inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id,
      redirect_origin_display_id: payload['origin_display_id'].presence
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
