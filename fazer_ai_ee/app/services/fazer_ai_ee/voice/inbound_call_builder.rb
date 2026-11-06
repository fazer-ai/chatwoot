# `conversation` is the thread a caller that files its own messages already picked for the
# call, the way it picks one for a message; without it the call's ContactInbox decides.
module FazerAiEe::Voice::InboundCallBuilder
  def self.prepended(base)
    base.singleton_class.prepend(ClassMethods)
  end

  module ClassMethods
    def perform!(conversation: nil, **)
      new(conversation: conversation, **).perform!
    end
  end

  def initialize(conversation: nil, **)
    super(**)
    @conversation = conversation
  end

  private

  def resolve_conversation!(contact, contact_inbox)
    @conversation || super
  end
end
