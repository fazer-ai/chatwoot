# Somebody rang this account on WhatsApp.
#
# Chatwoot cannot answer a WhatsApp call -- there is no command for it in the contract and
# nothing in whatsmeow to build one on -- so what an inbox can do with a call is show that
# it happened, next to the conversation it happened in. That is an activity line, the same
# shape a group rename gets, and it is the whole of this handler.
#
# `call.terminate` is deliberately not routed here. Every call ends, so a second line per
# call would say nothing an agent can act on, and with `auto_reject` on it would always
# say the same thing.
class Whatsapp::Session::Inbound::Handlers::CallOffer < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    return :ignored unless capability?(:calls)
    return :ignored if payload.from.blank?

    inbound::Locks.with_chat_lock(inbox, payload.from.source_id) { write_the_line }
  end

  private

  # Prefixed, and not the raw call id: this shares a column with WhatsApp's message ids,
  # and the prefix is what keeps a call from ever being the target of an edit, a revoke
  # or a reaction that names the same string.
  def source_id = "call:#{payload.call_id}"

  def write_the_line
    # A redelivered offer is the same call, and the line is already in the thread. The
    # connector publishes one offer per call, but a redelivery crosses instances and the
    # dedupe there is per session.
    return :duplicate if payload.call_id.present? && find_message(source_id).present?

    contact_inbox = inbound::ContactResolver.new(inbox: inbox, party: payload.from, overwrite: true).perform
    return :ignored if contact_inbox.nil?

    contact = contact_inbox.contact
    # The same rule every inbound path applies: a blocked contact stops generating
    # messages and notifications.
    return :ignored if contact.blocked?

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
