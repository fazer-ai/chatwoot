# Somebody rang this account on WhatsApp.
#
# A call the agent cannot answer here is shown as having happened, next to the conversation
# it happened in. That is an activity line, the same shape a group rename gets.
#
# A call the agent can answer is the other branch: the offer carries the connector's WebRTC
# offer (`sdp`), and an installation with voice calling takes it up through `take_up_call`
# instead, the way it takes up a Cloud API call. The calling flow lives in the enterprise
# half, so here that hook takes nothing up.
#
# The end of a call writes no second line. Every call ends, so it would say nothing an agent
# can act on, and with `auto_reject` on it would always say the same thing.
class Whatsapp::Session::Inbound::Handlers::CallOffer < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    return :ignored unless capability?(:calls)
    return :ignored if payload.from.blank?

    inbound::Locks.with_chat_lock(inbox, payload.from.source_id) { write_the_line }
  end

  private

  # The outcome when the call was taken up by the calling flow, nil when it was not and the
  # line is written instead.
  def take_up_call(_contact_inbox) = nil

  # Refuses the call when the calling flow says the inbox takes no incoming calls, and is
  # then the outcome: a refused call files nothing, no contact, no thread and no line, the
  # way the Cloud API's refusal does. The connector refuses every call itself when calling
  # is off, so here there is none.
  def refuse_call = nil

  # Prefixed, and not the raw call id: this shares a column with WhatsApp's message ids,
  # and the prefix is what keeps a call from ever being the target of an edit, a revoke
  # or a reaction that names the same string.
  def source_id = "call:#{payload.call_id}"

  def write_the_line
    # A redelivered offer is the same call, and the line is already in the thread. The
    # connector publishes one offer per call, but a redelivery crosses instances and the
    # dedupe there is per session.
    return :duplicate if payload.call_id.present? && find_message(source_id).present?

    # Before anything about who is calling: a call refused on the inbox's instruction is
    # refused for a blocked contact too, who is otherwise filed nowhere.
    refused = refuse_call
    return refused if refused

    contact_inbox = inbound::ContactResolver.new(inbox: inbox, party: payload.from, overwrite: true).perform
    return :ignored if contact_inbox.nil?

    contact = contact_inbox.contact
    return :ignored if Whatsapp::BlockedSender.silenced?(contact, from_me: false)

    taken = take_up_call(contact_inbox)
    return taken if taken

    conversation = inbound::ConversationFinder.new(
      inbox: inbox, contact: contact, contact_inbox: contact_inbox, occurred_at: occurred_at
    ).perform

    write(conversation, contact)
    :handled
  end

  def write(conversation, contact)
    conversation.messages.create!(
      account_id: conversation.account_id,
      inbox_id: conversation.inbox_id,
      message_type: :activity,
      # Blank when the call carried no id. The column is not unique, and a line with no
      # id is better than dropping a call WhatsApp announced without one.
      source_id: payload.call_id.presence && source_id,
      content: line_for(contact),
      created_at: occurred_at || Time.current
    )
  end

  # Neutral about what happened next, because this layer does not know. With
  # `auto_reject` on the connector refused it; with the policy off the operator's phone
  # rang and they may well have answered it there. "Missed" would be a guess, and the
  # wrong one half the time.
  def line_for(contact)
    key = payload.video ? 'video' : 'voice'
    locale = account.locale || I18n.default_locale
    I18n.with_locale(locale) do
      I18n.t("conversations.activity.whatsapp_call.#{key}", contact_name: display_name(contact))
    end
  end

  def display_name(contact)
    contact.name.presence || contact.phone_number.presence || contact.identifier
  end

  # The call's own instant, so a line written from a redelivery minutes later is dated
  # when the phone rang rather than when this job got to it.
  def occurred_at
    return if payload.timestamp.blank?

    Time.zone.at(payload.timestamp / 1000.0)
  end
end

Whatsapp::Session::Inbound::Handlers::CallOffer.prepend_mod_with('Whatsapp::Session::Inbound::Handlers::CallOffer')
