# Applies what the connector reported for a placed call before the call was recorded. See
# Whatsapp::ConnectorCallService#reconcile.
class Whatsapp::ConnectorCallReconcileJob < ApplicationJob
  queue_as :high

  # Long enough for the tab that placed the call to have read the answer that names it.
  DELAY = 3.seconds

  def perform(call_id)
    call = Call.whatsapp.find_by(id: call_id)
    return if call.nil?

    Whatsapp::ConnectorCallService.new(inbox: call.inbox).reconcile(call)
  end
end
