# Common ground for every inbound handler: what the event is about, and the three
# answers a handler may give.
#
#   :handled   the event changed something
#   :ignored   the event is not actionable here (disabled capability, unknown chat...)
#   :duplicate the event had already been processed
class Whatsapp::Session::Inbound::Handlers::Base
  Model = Whatsapp::Session::Model
  Inbound = Whatsapp::Session::Inbound

  attr_reader :channel, :event

  def initialize(channel:, event:)
    @channel = channel
    @event = event
  end

  def perform
    raise NotImplementedError, "#{self.class} must implement #perform"
  end

  private

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

  def find_message(source_id)
    return if source_id.blank?

    inbox.messages.find_by(source_id: source_id)
  end
end
