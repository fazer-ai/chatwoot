# The on-demand half of history sync: the operator asks, on the inbox's settings screen,
# for the phone to hand over what came before.
#
# The connect-time half needs no job. Subscribing to the event is the whole trigger there:
# the phone dumps what it has of its own accord once the session is up. This one is for
# afterwards, and for the conversations the inbox already holds.
#
# Nothing here waits for messages. Each request is acknowledged and answered later on the
# webhook, or not answered at all: the provider is explicit that a sleeping phone may
# never respond, so what the operator is told is that the request went out.
class Whatsapp::Session::HistoryBackfillJob < ApplicationJob
  queue_as :low

  # How many chats one press asks about. A cap rather than a page: the phone ignores the
  # count on a request (one instance answered a request for fifty messages with nine
  # hundred and forty seven), so the only thing bounding an import is how many chats were
  # asked, and every one of them can come back with a year of conversation.
  CHATS = 25

  def perform(channel)
    return unless channel.try(:session_capabilities)&.include?('history_sync')

    facade = channel.provider_service

    # Before the first request, because it is what puts `history` on the instance's
    # webhook subscription and what tells the import that these frames were asked for.
    Whatsapp::Session::HistoryBackfill.open!(channel)
    contacts(channel).each { |contact| request(facade, contact, channel) }
  end

  private

  # Most recently active first, which is where an operator asking for history is looking.
  # Read off conversations rather than contacts: a contact's own activity stamp moves for
  # reasons that have nothing to do with this inbox.
  def contacts(channel)
    channel.inbox.conversations.order(last_activity_at: :desc).limit(CHATS).includes(:contact).filter_map(&:contact).uniq
  end

  # One failure does not end the walk. A number that is no longer on WhatsApp, or a chat
  # the provider refuses, says nothing about the next one, and the operator pressed a
  # button that means "as much as you can get".
  def request(facade, contact, channel)
    facade.request_history(contact)
  rescue Whatsapp::Session::Errors::Error => e
    Rails.logger.warn("[WHATSAPP SESSION] history request failed for contact ##{contact.id} on inbox ##{channel.inbox&.id}: #{e.message}")
  end
end
