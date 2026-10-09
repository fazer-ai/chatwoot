# The connector's call events, filed the way Whatsapp::IncomingCallService files Meta's.
#
# The connector stands where Meta stands, so everything after the event arrives is the
# Cloud path's: the `Call` record, the call message, the conversation's call status, the
# broadcasts the browser rings and connects on, and the terminate status. What differs is
# only how an event names things. Meta's caller is a webhook contact to resolve; the
# connector's is a contact the session layer already resolved, so the call lands on the
# same thread that contact's messages do. And the connector delivers a session's events in
# order on one shard, so a terminate never overtakes its offer and needs no tombstone.
class Whatsapp::ConnectorCallService < Whatsapp::IncomingCallService
  def initialize(inbox:, contact_inbox: nil)
    super(inbox: inbox, params: {})
    @contact_inbox = contact_inbox
  end

  # A call.offer carrying the connector's WebRTC offer. With incoming calls turned off the
  # connector is told to refuse it, since it was asked to let calls ring (`calls.answer`)
  # so that the inbox can still place them; the activity line is then the caller's to write.
  def offer(payload)
    unless inbox.channel.inbound_calls_enabled?
      inbox.channel.provider_service.reject_call(payload.call_id, from: payload.from.address)
      return false
    end

    create_inbound_call(id: payload.call_id, session: { sdp_type: 'offer', sdp: payload.sdp })
    true
  end

  # The callee picked up. Meta tells the two halves of that apart, the tunnel coming up and
  # the pickup, and the connector reports them as one event, so both broadcasts go out.
  def answered(payload)
    call = Call.whatsapp.find_by(inbox_id: inbox.id, provider_call_id: payload.call_id)
    return unless call&.outgoing?

    accept_outbound_call(call, session: { sdp: payload.sdp })
    mark_outbound_accepted(call, {})
  end

  # A call shown only as an activity line has no record to close.
  def terminate(payload)
    call = Call.whatsapp.find_by(inbox_id: inbox.id, provider_call_id: payload.call_id)
    return if call.nil?

    finalize_terminate(call, nil, payload.reason)
  end

  private

  def build_inbound_call(payload, sdp_offer)
    extra_meta = { 'sdp_offer' => sdp_offer, 'ice_servers' => Call.default_ice_servers }
    Voice::InboundCallBuilder.perform!(
      inbox: inbox, call_sid: payload[:id], provider: :whatsapp, extra_meta: extra_meta,
      caller: { source_ids: [@contact_inbox.source_id], contact_attributes: {} }
    )
  end
end
