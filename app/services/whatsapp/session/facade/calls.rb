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

  def accept_call(call_id, sdp_answer)
    calls_supported!
    backend.accept_call(model::Commands::CallAccept.new(call_id: call_id, sdp: sdp_answer))
    true
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

  # The connector dials a phone number and nothing else. A conversation hands over its
  # contact's source id, which on this provider is the LID when the contact has one, so the
  # number is read off the contact behind it.
  def callee_address(recipient)
    contact = channel.inbox.contact_inboxes.find_by(source_id: recipient.to_s)&.contact
    phone = contact ? contact.phone_number : recipient
    model::Address.phone(phone) || raise(Whatsapp::Session::Errors::InvalidPayload, 'the contact has no phone number to call')
  end

  def caller_address(call_id)
    call = Call.whatsapp.find_by(inbox_id: channel.inbox.id, provider_call_id: call_id)
    address = call && model::Address.for_contact(call.contact)
    address || raise(Whatsapp::Session::Errors::InvalidPayload, "no caller recorded for call #{call_id}")
  end
end
