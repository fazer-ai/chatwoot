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

  # A call.offer carrying the connector's WebRTC offer, which rings as a Call. The address
  # it came from is kept on the call, since that is what refusing it names, and the
  # contact's own fields can be edited or merged away while it rings.
  # A redelivered offer is the call already ringing, or already answered: ringing the
  # agents again for it would put back the card an accept took away.
  def offer(payload)
    return if find_call(payload.call_id)

    @caller = payload.from.address
    create_inbound_call(id: payload.call_id, session: { sdp_type: 'offer', sdp: payload.sdp })
  end

  # Incoming calls turned off: the connector is told to refuse the call, by the address the
  # offer named. It was asked to let calls ring (`calls.answer`) so that the inbox can still
  # place them, and it has nobody else to refuse them.
  def refuse(payload)
    inbox.channel.provider_service.reject_call(payload.call_id, from: payload.from.address)
  end

  # The callee picked up. Meta tells the two halves of that apart, the tunnel coming up and
  # the pickup, and the connector reports them as one event, so both broadcasts go out.
  #
  # A pickup can beat the record of the call it answers: `call.start` answers once the
  # phone rings, and the Call is written after that answer. Such an answer is kept for
  # `reconcile`, since nothing will deliver it again.
  def answered(payload)
    call = find_call(payload.call_id)
    return keep_pending(payload.call_id, 'answered', 'sdp' => payload.sdp) if call.nil?
    return unless call.outgoing?

    accept_outbound_call(call, session: { sdp: payload.sdp })
    mark_outbound_accepted(call, {})
  end

  # A call shown only as an activity line has no record to close; one being placed may not
  # have its record yet, and is kept for `reconcile` like an answer.
  #
  # The connector reports no duration, so an answered call is timed from its pickup, as
  # the agent's own hang-up is.
  def terminate(payload)
    call = find_call(payload.call_id)
    return keep_pending(payload.call_id, 'terminate', 'reason' => payload.reason) if call.nil?

    # A pickup kept for a call recorded since, and not applied yet, happened before this
    # end: applied first, so the call is ended as the answered call it was.
    early = take_pending(call.provider_call_id, 'answered')
    answered(model::Events::CallAnswered.new(call_id: call.provider_call_id, sdp: early['sdp'])) if early
    call.reload if early
    duration = (Time.current - call.started_at).to_i if call.in_progress? && call.started_at
    finalize_terminate(call, duration, payload.reason)
  end

  # Applies what arrived for a placed call before it was recorded, in the order it happened.
  # Run a moment after the request that recorded it, from Whatsapp::ConnectorCallReconcileJob:
  # the tab that placed the call learns of it from that request's answer, and a pickup or
  # an end broadcast before then reaches a tab that does not know the call yet.
  def reconcile(call)
    answer = take_pending(call.provider_call_id, 'answered')
    answered(model::Events::CallAnswered.new(call_id: call.provider_call_id, sdp: answer['sdp'])) if answer
    ended = take_pending(call.provider_call_id, 'terminate')
    terminate(model::Events::CallTerminate.new(call_id: call.provider_call_id, from: nil, reason: ended['reason'])) if ended
  end

  # The connector could not use the agent's answer, and the call it was for goes on ringing
  # on the caller's phone. It is closed here as failed, and refused there, so neither side
  # is left believing it was picked up.
  def accept_failed(call_id)
    call = find_call(call_id)
    return if call.nil? || call.terminal?

    finalize_terminate(call, nil, 'accept_failed')
    inbox.channel.provider_service.reject_call(call_id)
  rescue Whatsapp::Session::Errors::Error => e
    Rails.logger.warn("[WHATSAPP CALL] refusing call #{call_id} after its answer failed: #{e.message}")
  end

  # Kept as long as the request that places a call can take to record it.
  PENDING_TTL = 60

  private

  def model = Whatsapp::Session::Model

  def find_call(call_id)
    Call.whatsapp.find_by(inbox_id: inbox.id, provider_call_id: call_id)
  end

  def keep_pending(call_id, kind, data)
    Redis::Alfred.setex(pending_key(call_id, kind), data.to_json, PENDING_TTL)
  end

  def take_pending(call_id, kind)
    raw = Redis::Alfred.get(pending_key(call_id, kind))
    return if raw.blank?

    Redis::Alfred.delete(pending_key(call_id, kind))
    JSON.parse(raw)
  end

  def pending_key(call_id, kind)
    format(Redis::Alfred::WHATSAPP_CONNECTOR_CALL_PENDING, inbox_id: inbox.id, call_id: call_id, kind: kind)
  end

  def build_inbound_call(payload, sdp_offer)
    extra_meta = { 'sdp_offer' => sdp_offer, 'ice_servers' => Call.default_ice_servers, 'caller_address' => @caller&.to_h }
    Voice::InboundCallBuilder.perform!(
      inbox: inbox, call_sid: payload[:id], provider: :whatsapp, extra_meta: extra_meta,
      caller: { source_ids: [@contact_inbox.source_id], contact_attributes: {} }
    )
  end
end
