# A batch of history: what the phone sends after pairing, and what it answers a request
# with. Both arrive under the same event, discriminated by `kind`.
class Whatsapp::Session::Inbound::Handlers::HistorySync < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    return :ignored unless capability?(:history_sync)
    # `chats` and `labels` are the provider's own CRM objects and the account's WhatsApp
    # labels. Only messages are imported, and a kind this layer does not know is dropped
    # rather than guessed at.
    return :ignored unless payload.kind == 'messages'
    return :ignored if messages.empty?

    inbound::HistoryImporter.new(channel: channel, messages: messages, requested: asked_for?).perform
  end

  private

  # Whether anybody asked, which decides how much of the pile is kept rather than whether
  # any of it is. The setting is standing consent given on the inbox; the window is one
  # person having pressed the button. Neither means the phone is offering its history
  # unprompted, and then the importer files only what arrived while the session was down.
  #
  # That last case is the whole reason this no longer refuses outright. WhatsApp has no way
  # to ask for messages *after* a point: the on-demand request only walks backwards, and
  # the phone's own account of what was missed arrives on its own after a pairing. Refusing
  # it threw away the only copy of the weekend.
  def asked_for?
    return true if channel.provider_service.try(:history_sync?)
    return false unless Whatsapp::Session::HistoryBackfill.pending?(channel)

    # Held open for as long as the answer keeps coming: a dump arrives in several frames,
    # and a window closing between two of them would drop the tail of the import it
    # authorised in the first place.
    Whatsapp::Session::HistoryBackfill.open!(channel)
    true
  end

  # The batch is carried as plain hashes, the shape the contract puts on the wire, so each
  # is rehydrated here into the same InboundMessage the live path reads.
  def messages
    @messages ||= Array(payload.data.to_h['messages']).map { |raw| model::InboundMessage.from_h(raw) }
  end
end
