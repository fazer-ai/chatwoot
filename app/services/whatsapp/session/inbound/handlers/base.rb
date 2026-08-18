# Common ground for every inbound handler: what the event is about, and the three
# answers a handler may give.
#
#   :handled   the event changed something
#   :ignored   the event is not actionable here (disabled capability, unknown chat...)
#   :duplicate the event had already been processed
class Whatsapp::Session::Inbound::Handlers::Base
  attr_reader :channel, :event

  def initialize(channel:, event:)
    @channel = channel
    @event = event
  end

  def perform
    raise NotImplementedError, "#{self.class} must implement #perform"
  end

  private

  # Resolved on every call, never held in a constant. Both are implicit namespaces (no
  # `model.rb`, no `inbound.rb`), so a constant here captures a module object that a
  # reload strips of its autoloads, and every handler inheriting it then raises
  # `uninitialized constant` on the first lookup through it. Asking for the full path
  # each time is what makes the tree survive a reload.
  def model = Whatsapp::Session::Model
  def inbound = Whatsapp::Session::Inbound

  def payload = event.payload
  def inbox = channel.inbox
  def account = inbox.account

  def capability?(capability)
    channel.session_capabilities.include?(capability.to_s)
  end

  # Chats Chatwoot has no representation for. The connector already drops most of them,
  # but a hosted API forwards everything its instance sees.
  def ignorable_chat?(address)
    address.blank? || address.ignorable?
  end

  def find_message(source_id) = find_messages(source_id).first

  # A shared-contact payload is stored as one row per card, all carrying the provider's
  # single id, which is how the Baileys layer and the Cloud provider store it too.
  # Anything mutating a message by that id therefore has to reach every row, or a revoke
  # takes one card off the screen and leaves the rest of the share behind.
  def find_messages(source_id)
    return Message.none if source_id.blank?

    inbox.messages.where(source_id: source_id).order(:id)
  end
end
