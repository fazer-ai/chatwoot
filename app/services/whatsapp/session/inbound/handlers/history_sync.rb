# A batch of history: what the phone sends after pairing, and what it answers a request
# with. Both arrive under the same event, discriminated by `kind`.
#
# Queued rather than filed here. A pairing dump is hundreds of slices, and on the
# connector's consumer each one held the shard for as long as it took to write, with every
# live event of every session on the shard behind it. Each slice becomes a
# Whatsapp::Session::HistoryImportJob, which takes an import slot and the chat lock before
# it writes, the way the Baileys import does. The connector already cuts the dump into one
# slice per chat, so nothing is regrouped on the way.
class Whatsapp::Session::Inbound::Handlers::HistorySync < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    return :ignored unless capability?(:history_sync)
    # `chats` and `labels` are the provider's own CRM objects and the account's WhatsApp
    # labels. Only messages are imported, and a kind this layer does not know is dropped
    # rather than guessed at.
    return :ignored unless payload.kind == 'messages'
    return :ignored if messages.empty? && exhausted.nil?

    Whatsapp::Session::HistoryImportJob.perform_later(
      inbox, messages, inbound::Coverage.watermark(inbox), asked_for?, **filing
    )
    :handled
  end

  private

  def data = @data ||= payload.data.to_h.stringify_keys

  # The slice as the wire carried it: the job rehydrates each message into the same
  # InboundMessage the live path reads.
  def messages = @messages ||= Array(data['messages'])

  # Only the connector types the slice. `on_demand` exists only as the answer to a request
  # somebody made from a thread, which makes it both asked for and watched.
  def on_demand? = data['sync'] == 'on_demand'

  # The chat the phone has nothing older for. Said on the last slice of an answer, which
  # can be empty: then it is the whole message.
  def exhausted
    return unless ActiveModel::Type::Boolean.new.cast(data['exhausted'])

    chat = data['chat']
    chat.present? ? model::Address.from_h(chat) : nil
  end

  # Left off when there is nothing to say, so a job queued by this build stays readable by
  # the build before it for everything but what this build added.
  def filing
    filing = { announce: on_demand?, identity: Whatsapp::Session::HistoryImportJob.identity(channel) }
    filing[:group_name] = data['name'] if data['name'].present?
    filing[:exhausted] = exhausted.to_h if exhausted
    filing
  end

  # Whether anybody asked, which decides how much of the pile is kept rather than whether
  # any of it is. The answer to a request says so itself when the provider types it. The
  # setting is standing consent given on the inbox; the window is one person having
  # pressed the button. None of them means the phone is offering its history
  # unprompted, and then the importer files only what arrived while the session was down.
  #
  # That last case is the whole reason this no longer refuses outright. WhatsApp has no way
  # to ask for messages *after* a point: the on-demand request only walks backwards, and
  # the phone's own account of what was missed arrives on its own after a pairing. Refusing
  # it threw away the only copy of the weekend.
  def asked_for?
    return true if on_demand?
    return true if channel.provider_service.try(:history_sync?)
    return false unless Whatsapp::Session::HistoryBackfill.pending?(channel)

    # Held open for as long as the answer keeps coming: a dump arrives in several frames,
    # and a window closing between two of them would drop the tail of the import it
    # authorised in the first place.
    Whatsapp::Session::HistoryBackfill.open!(channel)
    true
  end
end
