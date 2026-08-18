# The provider service of a session channel.
#
# Channel::Whatsapp talks to its provider in the shape the legacy providers established:
# a recipient id that is a phone number or a JID, a Chatwoot message, a group JID. This
# translates all of it into the canonical commands the backend takes, so the channel
# model, the group controllers and the presence services keep working untouched.
#
# Session-internal code does not come through here: it asks the channel for
# `session_backend` and speaks the canonical API directly.
class Whatsapp::Session::Facade
  include Whatsapp::Session::Facade::Groups

  TYPING_STATES = {
    Events::Types::CONVERSATION_TYPING_ON => 'composing',
    Events::Types::CONVERSATION_RECORDING => 'recording',
    Events::Types::CONVERSATION_TYPING_OFF => 'paused'
  }.freeze

  attr_reader :channel, :backend

  # Resolved on every call, never held in a constant: `Whatsapp::Session::Model` is an
  # implicit namespace (there is no model.rb), so a constant here captures a module
  # object that a reload strips of its autoloads, and every lookup through it then
  # raises `uninitialized constant`.
  def model = Whatsapp::Session::Model

  def initialize(channel)
    @channel = channel
    @backend = Whatsapp::Session::Registry.backend_for(channel)
  end

  # --- session lifecycle ---------------------------------------------------------

  # "Make sure this session is up": resumes an existing pairing, or starts a new one.
  def setup_channel_provider
    mode = pairing_mode
    state = backend.connect(
      model::Commands::SessionConnect.new(
        pairing: mode, phone: channel.phone_number.to_s.delete('+'),
        groups: capability?('groups'), calls: capability?('calls')
      )
    )
    # The connect answer is the first state the dashboard has to show (it carries the QR
    # for a provider that returns one), and for a polled backend it is also what starts
    # the pairing poll: nothing else would refresh the code as it rotates.
    Whatsapp::Session::ConnectionStateWriter.new(channel).apply(state)
    Whatsapp::Session::PairingPollJob.perform_later(channel, pairing: mode) if backend.class.state_polling?
    state
  end

  def import_session(session:, candidate_index: 0)
    backend.import_session(session: session, candidate_index: candidate_index)
  end

  def disconnect_channel_provider
    backend.disconnect
  end

  # Session providers pair a real phone: there is no template catalog to sync and no
  # template to send.
  def sync_templates
    true
  end

  def send_template(_recipient_id, _template_info, _message = nil)
    raise Whatsapp::Session::Errors::NotSupported, 'templates are a cloud API feature'
  end

  # --- messages ------------------------------------------------------------------

  def send_message(_recipient_id, message)
    Whatsapp::Session::Outbound::MessageSender.new(message).perform
  end

  def edit_message(recipient_id, message, new_content)
    backend.edit_message(
      model::Commands::MessageEdit.new(
        message_id: Whatsapp::Session::Outbound::SourceIdReservation.generate,
        target_id: message.source_id, to: address(recipient_id),
        content: model::Content::Text.new(body: new_content)
      )
    )
  end

  def delete_message(recipient_id, message)
    return if message.source_id.blank?

    to = address(recipient_id)
    backend.revoke_message(
      model::Commands::MessageRevoke.new(
        target_id: message.source_id, to: to,
        participant: (model::Address.for_contact(message.sender) if to.group? && message.incoming?)
      )
    )
  end

  def read_messages(messages, recipient_id:, **)
    source_ids = Array(messages).filter_map(&:source_id)
    return if source_ids.empty?

    backend.mark_read(model::Commands::MessageMarkRead.new(chat: address(recipient_id), message_ids: source_ids))
  end

  def unread_message(recipient_id, message)
    backend.mark_unread(
      model::Commands::MessageMarkUnread.new(
        chat: address(recipient_id), last_message_id: message.source_id, from_me: message.outgoing?
      )
    )
  end

  # The provider acknowledges delivery itself as it takes the message off WhatsApp;
  # there is nothing for Chatwoot to send back.
  def received_messages(_recipient_id, _messages)
    true
  end

  # --- presence and contacts -----------------------------------------------------

  def toggle_typing_status(typing_status, recipient_id:, **)
    state = TYPING_STATES[typing_status]
    return if state.blank?

    backend.send_chat_presence(model::Commands::ChatPresence.new(chat: address(recipient_id), state: state))
  end

  def update_presence(status)
    backend.update_presence(model::Commands::PresenceSet.new(state: status))
  end

  def presence_subscribe(jids)
    Array(jids).each do |jid|
      party = model::Party.from_address(model::Address.parse(jid))
      next if party.blank?

      backend.subscribe_presence(model::Commands::PresenceSubscribe.new(party: party))
    end
  end

  # Answered in the shape the contact builder and the inbox controller already read:
  # `exists` plus the JID WhatsApp actually knows the number by, which is what the
  # ninth-digit normalization needs.
  def on_whatsapp(recipient_id)
    digits = recipient_id.to_s.split('@').first.to_s.delete('+')
    check = backend.check_numbers(model::Commands::ContactCheck.new(phones: [digits])).first
    return { 'jid' => "#{digits}@s.whatsapp.net", 'exists' => false } if check.blank?

    { 'jid' => (check.address || model::Address.phone(check.phone)).to_jid, 'exists' => check.exists }
  end

  private

  def capability?(capability)
    channel.session_capabilities.include?(capability)
  end

  # A session that was already paired resumes; one that never was needs a QR (a pairing
  # code is requested explicitly from the dashboard).
  def pairing_mode
    channel.provider_connection['phone_number'].present? ? 'resume' : 'qr'
  end

  # Recipient ids reach the channel as bare phone numbers or as JIDs, depending on the
  # caller and on whether the contact has a LID.
  def address(recipient_id)
    recipient_id.to_s.include?('@') ? model::Address.parse(recipient_id) : model::Address.phone(recipient_id)
  end
end
