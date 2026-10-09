# The call half of the facade: what `Whatsapp::CallService` and the calls controller ask
# of a WhatsApp provider, in the shape the Cloud service answers them, translated into the
# connector's call commands. The connector stands where Meta stands, so the flow, the
# `Call` record and the browser side are the ones the Calling API already drives.
#
# Each method answers true once the command is on its way, which is what the Cloud service
# answers once Meta took the request: the outcome of a call arrives as events, and a
# command the connector could not carry out comes back as `command.failed`.
module Whatsapp::Session::Facade::Calls
  # The Calling API takes the browser's answer in two steps, and the connector in one.
  def pre_accept_call(_call_id, _sdp_answer)
    calls_supported!
    true
  end

  # The answer is fire and forget, so a connector that cannot use it says so later, as a
  # `command.failed` naming this command and not the call. The command is remembered
  # against the call for as long as such a failure could take to come back, and a failure
  # that came back already is this call failing, the way the Cloud service answers false.
  def accept_call(call_id, sdp_answer)
    calls_supported!
    command_id = backend.accept_call(model::Commands::CallAccept.new(call_id: call_id, sdp: sdp_answer))
    command_id.blank? || Whatsapp::Session::CallCommands.remember(command_id, call_id)
  end

  # The connector refuses a call by naming who placed it. A call refused as it arrives is
  # refused with the caller the offer named; one refused from the ringing widget is read
  # off the call this inbox recorded.
  def reject_call(call_id, from: nil)
    calls_supported!
    backend.reject_call(model::Commands::CallReject.new(call_id: call_id, from: from || caller_address(call_id)))
    true
  end

  def terminate_call(call_id)
    calls_supported!
    backend.terminate_call(model::Commands::CallTerminate.new(call_id: call_id))
    true
  end

  # Answers in the Cloud service's shape, so the controller reads the call id the same way
  # for both. Keyed on the offer itself: a retried request carrying the same offer is the
  # same call, and the connector answers it without ringing the phone again.
  def initiate_call(recipient, sdp_offer)
    calls_supported!
    command = model::Commands::CallStart.new(to: callee_address(recipient), sdp: sdp_offer)
    { 'call_id' => backend.start_call(command, idempotency_key: "call:#{Digest::SHA256.hexdigest(sdp_offer.to_s)}") }
  end

  private

  def calls_supported!
    return if capability?('voice_calls')

    raise Whatsapp::Session::Errors::NotSupported, "#{provider} does not carry calls"
  end

  # The connector dials a phone number and nothing else. A conversation hands over the
  # identity its thread is on, a number or a LID, and is called on that identity, never on
  # the contact's own number, which after an edit or a merge can belong to somebody else.
  # A source id is bare digits either way and nothing on the contact reliably says which
  # (a merge keeps the other contact's identifier), so the connector, which knows the
  # pairing, is asked for the number behind it as a LID. One it pairs with nothing is
  # dialled as a number only when something says it is one: the contact's own number, or
  # the connector knowing it as a number. Anything else is refused, because the digits of
  # a LID dialled as a number can be a stranger's phone.
  def callee_address(recipient)
    recipient = recipient.to_s.delete('+')
    phone = paired_phone(model::Address.lid(recipient)) || (recipient if known_number?(recipient))
    model::Address.phone(phone) || raise(Whatsapp::Session::Errors::InvalidPayload, 'no phone number to call this conversation on')
  end

  # A contact of this account carrying the number says it is one: that is also what a call
  # placed from the contact panel hands over, before any thread with the contact exists.
  # The connector answers an address it holds nothing for with that same address alone, so
  # a number is known to it only when the answer also carries the LID it pairs with.
  def known_number?(recipient)
    channel.account.contacts.exists?(phone_number: "+#{recipient}") || resolve(model::Address.phone(recipient))&.lid.present?
  end

  def paired_phone(lid) = resolve(lid)&.phone.presence

  def resolve(address)
    backend.resolve_contact(model::Commands::ContactResolve.new(party: address))
  end

  # The address the offer named, kept on the call when it rang, and read off its contact
  # only for a call recorded without one.
  def caller_address(call_id)
    call = Call.whatsapp.find_by(inbox_id: channel.inbox.id, provider_call_id: call_id)
    recorded = call&.meta&.dig('caller_address')
    address = recorded ? model::Address.from_h(recorded) : call && model::Address.for_contact(call.contact)
    address || raise(Whatsapp::Session::Errors::InvalidPayload, "no caller recorded for call #{call_id}")
  end
end
