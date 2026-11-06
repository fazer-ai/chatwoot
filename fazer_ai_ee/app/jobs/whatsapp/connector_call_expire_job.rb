# Ends an incoming connector call still ringing past what WhatsApp rings. See
# Whatsapp::ConnectorCallService#expire_unanswered.
class Whatsapp::ConnectorCallExpireJob < ApplicationJob
  queue_as :high

  def perform(call_id)
    call = Call.whatsapp.find_by(id: call_id)
    return if call.nil?

    Whatsapp::ConnectorCallService.new(inbox: call.inbox).expire_unanswered(call)
  end
end
