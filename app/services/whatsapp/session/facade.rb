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

  attr_reader :channel, :backend, :provider, :instance

  # Resolved on every call, never held in a constant: `Whatsapp::Session::Model` is an
  # implicit namespace (there is no model.rb), so a constant here captures a module
  # object that a reload strips of its autoloads, and every lookup through it then
  # raises `uninitialized constant`.
  def model = Whatsapp::Session::Model

  def initialize(channel)
    @channel = channel
    @backend = Whatsapp::Session::Registry.backend_for(channel)
    # The provider this backend was resolved for, and the instance it was pointed at. An
    # inbox converted while a connect is in flight has an empty connection record belonging
    # to another provider; one re-pointed at another instance of the same provider keeps
    # its key and changes nothing the provider fence can see, while the answer in flight
    # can name a different phone, which reads as a wrong-number quarantine and ends the
    # session that just replaced it. Every write below is fenced against landing there.
    @provider = channel.provider
    @instance = Whatsapp::Session::Registry.instance_fingerprint(channel)
  end

  # --- session lifecycle ---------------------------------------------------------

  # "Make sure this session is up": resumes an existing pairing, or starts a new one.
  def setup_channel_provider
    end_disowned_session
    mode = pairing_mode
    attempt = claim_pairing_attempt
    # The inbox was converted while this was running, so it is not this backend's to
    # connect: asking the old provider anyway leaves a session behind that no inbox owns.
    return if attempt.nil?

    state = connect(mode, attempt)
    # The connect answer is the first state the dashboard has to show (it carries the QR
    # for a provider that returns one), and for a polled backend it is also what starts
    # the pairing poll: nothing else would refresh the code as it rotates. A resume that
    # answers `open` has nothing left to poll, and a chain started over one would write
    # `connect_failure` over a healthy connection the first time a request failed.
    writer.apply(state.with_attempt(attempt), reset: true, attempt: attempt, provider: provider, instance: instance)
    start_pairing_poll(mode, attempt) if state.connecting? && backend.class.state_polling?
    state
  end

  def import_session(session:, candidate_index: 0)
    backend.import_session(session: session, candidate_index: candidate_index)
  end

  # The channel calls this when an inbox is destroyed or converted to another provider,
  # so it is a teardown, not a pause: the Baileys service answers it with
  # `DELETE /connections/<phone>`. Merely disconnecting would leave the pairing and its
  # credentials alive on the provider under a session id Chatwoot no longer has.
  def disconnect_channel_provider
    backend.delete_session
  rescue Whatsapp::Session::Errors::NotSupported
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

  # One command per participant in a group. A receipt on WhatsApp is addressed by the
  # message key, and in a group that key includes who sent it, so a single command
  # covering several senders cannot be acknowledged. In a 1:1 chat the peer is the chat
  # itself and the field stays empty.
  def read_messages(messages, recipient_id:, **)
    return unless capability?('read_receipts')

    chat = address(recipient_id)
    readable = Array(messages).select { |message| message.source_id.present? }
    readable.group_by { |message| chat.group? ? message.sender : nil }.each do |sender, group|
      backend.mark_read(
        model::Commands::MessageMarkRead.new(
          chat: chat, message_ids: group.map(&:source_id), sender: participant_address(group.first, sender)
        )
      )
    end
  end

  # Addressed from the conversation's contact rather than from `recipient_id`: the
  # channel always hands this one `contact.phone_number`, which for a LID contact is not
  # the id WhatsApp knows the chat by, and for a LID-only contact is nothing at all.
  def unread_message(recipient_id, message)
    return unless capability?('mark_unread')

    contact = message.conversation&.contact
    chat = contact.present? ? model::Address.for_contact(contact) : address(recipient_id)

    backend.mark_unread(
      model::Commands::MessageMarkUnread.new(
        chat: chat, last_message_id: message.source_id, from_me: message.outgoing?
      )
    )
  end

  # The provider acknowledges delivery itself as it takes the message off WhatsApp;
  # there is nothing for Chatwoot to send back.
  def received_messages(_recipient_id, _messages)
    true
  end

  # --- presence and contacts -----------------------------------------------------
  #
  # These four are background synchronization the dashboard triggers as a side effect of
  # something else: a listener firing on a typing event, a conversation being marked
  # unread. `Channel::Whatsapp` used to skip them by asking `respond_to?`, which was true
  # of the legacy service and false of anything it did not implement; a facade that
  # answers every message makes that test useless, so the capability is what decides now.
  # Nothing here is an action the agent waits on, so an unsupported one is skipped rather
  # than raised: a listener that raises takes the whole event down with it.

  def toggle_typing_status(typing_status, recipient_id:, **)
    state = TYPING_STATES[typing_status]
    return if state.blank? || !capability?('typing')

    backend.send_chat_presence(model::Commands::ChatPresence.new(chat: address(recipient_id), state: state))
  end

  # `online`, `offline` and `busy` are Chatwoot availability; the contract knows only
  # `available` and `unavailable`. The same mapping the Baileys service has.
  PRESENCE_STATES = { 'online' => 'available', 'offline' => 'unavailable', 'busy' => 'unavailable' }.freeze

  def update_presence(status)
    return unless capability?('presence')

    state = PRESENCE_STATES[status.to_s]
    return if state.blank?

    backend.update_presence(model::Commands::PresenceSet.new(state: state))
  end

  # The command's `party` field carries an Address, not a Party: `PresenceSubscribe`
  # coerces it as one, and `.new` does not run that coercion, so building a Party here
  # put `{phone, lid}` on the wire where the connector expects `{kind, id}`.
  def presence_subscribe(jids)
    return unless capability?('presence_subscribe')

    Array(jids).filter_map { |jid| model::Address.parse(jid) }.each do |address|
      backend.subscribe_presence(model::Commands::PresenceSubscribe.new(party: address))
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

  # An object in the contract, not a flag: the field says how calls are handled, and the
  # only policy this layer has is to reject them. Omitted when the backend does not do
  # calls at all, because `false` is not a value the schema accepts either.
  def call_policy
    { 'auto_reject' => true } if capability?('calls')
  end

  def writer
    Whatsapp::Session::ConnectionStateWriter.new(channel)
  end

  # Identifies this attempt, and claims it before the provider is asked rather than after
  # it answers. Two connects for the same inbox produce two polling chains, and without a
  # token the older one cannot tell that the QR on screen is no longer the one it was
  # following: it would time out over a live pairing. Claiming first also orders the two
  # by the click rather than by which provider call happens to answer first, which is what
  # the fence in the writer then enforces: the older answer, and its dead QR, is refused.
  def claim_pairing_attempt
    attempt = SecureRandom.uuid
    result = writer.apply(
      model::ConnectionState.new(connection: 'connecting', pairing_attempt: attempt), reset: true, provider: provider,
                                                                                      instance: instance
    )
    attempt if result == :written
  end

  # The claim above already moved the dashboard to "connecting". Leaving it there when the
  # provider refuses the connection parks the operator on a pairing that never started,
  # which is the same dead screen the poll's ceiling exists to prevent.
  def connect(mode, attempt)
    backend.connect(
      model::Commands::SessionConnect.new(
        pairing: mode, phone: channel.phone_number.to_s.delete('+'),
        groups: capability?('groups'), calls: call_policy
      )
    )
  rescue Whatsapp::Session::Errors::Error
    writer.apply(
      model::ConnectionState.new(connection: 'close', error: 'connect_failure'), attempt: attempt, provider: provider,
                                                                                 instance: instance
    )
    raise
  end

  # With the deadline resolved here, not by the worker. It is a ceiling on the attempt,
  # and a busy queue would otherwise hand a QR that expired while the job waited its own
  # two full minutes of polling on top of the wait.
  def start_pairing_poll(mode, attempt)
    Whatsapp::Session::PairingPollJob.perform_later(
      channel,
      pairing: mode, deadline_at: Whatsapp::Session::PairingPollJob.deadline_for(mode),
      fence: { provider: channel.provider, instance: instance, attempt: attempt }
    )
  end

  # Connecting again is the way out of a wrong-number quarantine, and the connect below
  # is what lifts it. The rejected account is still on the provider until its logout
  # lands, though, and that marker is the only thing keeping its chats out of this inbox:
  # lifting it first and pairing second would file somebody else's messages here for as
  # long as the new QR is on screen. So the wrong account goes before the marker does,
  # which also stands the asynchronous retry down before there is a new session for it to
  # kill. A provider that cannot be reached raises, and nothing was cleared or connected.
  def end_disowned_session
    return unless Whatsapp::Session::ConnectionStateWriter.disowned?(channel)

    backend.logout
    writer.apply(model::ConnectionState.new(connection: 'close'), reset: true, provider: provider, instance: instance)
  rescue Whatsapp::Session::Errors::NotSupported
    # A backend with no logout cannot be held in quarantine either: pairing again is the
    # only exit it has, and refusing that would leave the inbox with none at all.
    nil
  end

  # A session that was already paired resumes; one that never was needs a QR (a pairing
  # code is requested explicitly from the dashboard).
  def pairing_mode
    channel.provider_connection['phone_number'].present? ? 'resume' : 'qr'
  end

  # `sender_type` rather than a class check: the association can hold a User (an agent's
  # own message), and a class comparison is what a reload breaks.
  def participant_address(message, sender)
    return if sender.nil? || message.sender_type != 'Contact'

    model::Address.for_contact(sender)
  end

  # Recipient ids reach the channel as bare phone numbers or as JIDs, depending on the
  # caller and on whether the contact has a LID.
  def address(recipient_id)
    recipient_id.to_s.include?('@') ? model::Address.parse(recipient_id) : model::Address.phone(recipient_id)
  end
end
