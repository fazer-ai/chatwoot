require 'rails_helper'

RSpec.describe Whatsapp::Session::Facade do
  subject(:facade) { channel.provider_service }

  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:backend) { Whatsapp::Session::Backends::Fake.new(channel) }
  let(:contact) { create(:contact, account: channel.account, phone_number: '+5541999990000', identifier: '182736451928374@lid') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '182736451928374') }
  let(:conversation) { create(:conversation, contact: contact, contact_inbox: contact_inbox, inbox: inbox, account: channel.account) }

  before { allow(Whatsapp::Session::Registry).to receive(:backend_for).and_return(backend) }

  it 'is what a session channel answers with' do
    # Named rather than `described_class`, which RSpec captured when this file loaded: a
    # reload replaces the class, the channel builds an instance of the new one, and the
    # identity check fails on a facade that is perfectly correct.
    expect(facade).to be_a(Whatsapp::Session::Facade) # rubocop:disable RSpec/DescribedClass
    expect(channel.session_backend).to eq(backend)
  end

  describe 'read receipts' do
    it 'marks the stored messages read on WhatsApp' do
      message = create(:message, conversation: conversation, inbox: inbox, account: channel.account, source_id: '3EB0AAAA')

      channel.read_messages([message], conversation: conversation)

      expect(backend.last_command.message_ids).to eq(['3EB0AAAA'])
      expect(backend.last_command.chat.id).to eq('182736451928374')
    end

    it 'stays quiet when the inbox turned mark_as_read off' do
      channel.update!(provider_config: channel.provider_config.merge('mark_as_read' => false))
      message = create(:message, conversation: conversation, inbox: inbox, account: channel.account, source_id: '3EB0AAAA')

      channel.read_messages([message], conversation: conversation)

      expect(backend.commands).to be_empty
    end
  end

  it 'maps a typing indicator to the chat presence the provider expects' do
    channel.toggle_typing_status(Events::Types::CONVERSATION_RECORDING, conversation: conversation)

    expect(backend.last_command.state).to eq('recording')
  end

  it 'answers the on_whatsapp check in the shape the contact builder reads' do
    response = channel.on_whatsapp('+5541999990000')

    expect(response).to eq({ 'jid' => '5541999990000@s.whatsapp.net', 'exists' => true })
  end

  # The factory neutralizes Channel::Whatsapp#sync_templates, so the facade is asked directly.
  it 'has no templates to sync or to send' do
    expect(facade.sync_templates).to be(true)
    expect { channel.send_template('5541999990000', {}) }.to raise_error(Whatsapp::Session::Errors::NotSupported)
  end

  it 'persists the state the connect answered with, which is what carries the QR' do
    channel.setup_channel_provider

    expect(channel.reload.provider_connection).to include('connection' => 'connecting')
    expect(channel.provider_connection['qr_data_url']).to be_present
  end

  it 'starts the pairing poll only for a backend that has to be polled' do
    expect { channel.setup_channel_provider }.not_to have_enqueued_job(Whatsapp::Session::PairingPollJob)

    allow(backend.class).to receive(:state_polling?).and_return(true)

    # The attempt token is generated per connect, so it is matched by shape, not value.
    expect { channel.provider_service.setup_channel_provider }
      .to have_enqueued_job(Whatsapp::Session::PairingPollJob)
      .with(channel, hash_including(pairing: 'qr', provider: 'native'))
  end

  # Two connects racing: the operator clicking twice, or a second tab. Whichever provider
  # call answers last would otherwise be the state on screen even when it belongs to the
  # older attempt, and the poll driving the QR the operator is actually looking at would
  # read the record, find somebody else's token and retire itself.
  it 'refuses a connect answer for an attempt the inbox has already moved past' do
    allow(backend).to receive(:connect) do
      # The second click lands while this one is still waiting on the provider.
      channel.update_provider_connection!(
        { 'connection' => 'connecting', 'qr_data_url' => 'data:image/png;base64,NEWER', 'pairing_attempt' => 'attempt-2' }
      )
      Whatsapp::Session::Model::ConnectionState.new(connection: 'connecting', qr_data_url: 'data:image/png;base64,OLDER')
    end

    channel.provider_service.setup_channel_provider

    expect(channel.reload.provider_connection).to include(
      'qr_data_url' => 'data:image/png;base64,NEWER', 'pairing_attempt' => 'attempt-2'
    )
  end

  # The attempt is claimed before the provider is asked, which puts the dashboard on
  # "connecting" straight away. A refusal that left it there parks the operator on a
  # pairing that never started, with no poll running to ever correct it.
  it 'reports a refused connection instead of leaving the claim on screen' do
    allow(backend).to receive(:connect).and_raise(Whatsapp::Session::Errors::ProviderUnavailable)

    expect { channel.setup_channel_provider }.to raise_error(Whatsapp::Session::Errors::ProviderUnavailable)

    expect(channel.reload.provider_connection).to include('connection' => 'close', 'error_code' => 'connect_failure')
  end

  # Two operators, or two tabs: one converts the inbox while the other clicks connect.
  # The facade holds the backend of the provider it was built for, and the record now
  # belongs to another one, so connecting would leave a session behind that no inbox owns
  # and no operator can see.
  it 'does not connect an inbox that was converted while the request was running' do
    facade = channel.provider_service
    channel.update_columns(provider: 'uazapi') # rubocop:disable Rails/SkipsModelValidations

    expect(facade.setup_channel_provider).to be_nil
    expect(backend.commands).to be_empty
    expect(channel.reload.provider_connection).to eq({})
  end

  # The ceiling belongs to the attempt, not to the worker: a QR lives two minutes from
  # the moment the provider issued it, and a queue running ten minutes late would give
  # that dead code two more minutes of polling.
  it 'hands the poll a deadline counted from the connect, not from the worker' do
    allow(backend.class).to receive(:state_polling?).and_return(true)

    expect { channel.setup_channel_provider }.to(
      have_enqueued_job(Whatsapp::Session::PairingPollJob)
        .with { |_channel, options| expect(options[:deadline_at]).to be_within(5.seconds).of(2.minutes.from_now) }
    )
  end

  # A resume answers `open` when the pairing is still good. There is nothing left to poll
  # then, and a chain started over it would look current forever: the first request that
  # failed would write `connect_failure` over a healthy connection.
  it 'starts no poll for a connect that came back already paired' do
    allow(backend.class).to receive(:state_polling?).and_return(true)
    allow(backend).to receive(:connect).and_return(
      Whatsapp::Session::Model::ConnectionState.new(connection: 'open', phone_number: channel.phone_number.delete('+'))
    )

    expect { channel.setup_channel_provider }.not_to have_enqueued_job(Whatsapp::Session::PairingPollJob)

    expect(channel.reload.provider_connection).to include('connection' => 'open')
    expect(channel.provider_connection).not_to have_key('pairing_attempt')
  end

  # The inbound layer keeps an inbox paired with the wrong number quarantined, and no
  # event lifts that on its own: a state that names no number is refused precisely so a
  # pending logout cannot clear it. Connecting again is the operator's way out, so it
  # has to be the thing that clears it, or fixing the configured number changes nothing.
  it 'lifts a wrong-number quarantine when the operator connects again' do
    channel.update_provider_connection!(
      { 'connection' => 'close', 'error_code' => 'wrong_phone_number',
        'error' => I18n.t('errors.inboxes.channel.provider_connection.wrong_phone_number') }
    )

    channel.provider_service.setup_channel_provider

    expect(channel.reload.provider_connection).to include('connection' => 'connecting')
    expect(channel.provider_connection).not_to have_key('error_code')
  end

  # Lifting that marker is what lets the inbound layer file chats again, and the account
  # that was rejected is still on the provider until its logout lands: pairing first and
  # lifting second would file somebody else's messages here for as long as the new QR is
  # on screen. It also stands the asynchronous logout retry down before there is a new
  # session for it to kill.
  it 'ends the wrong account before it lifts the quarantine keeping that account out' do
    channel.update_provider_connection!({ 'connection' => 'close', 'error_code' => 'wrong_phone_number' })

    channel.provider_service.setup_channel_provider

    expect(backend.commands.map { |command| command.class.wire_type }).to eq(%w[session.logout session.connect])
  end

  # The quarantine is the only reason to end a session here. Doing it on every connect
  # would throw away a perfectly good pairing and cost the operator a fresh scan.
  it 'ends nothing when the inbox is not quarantined' do
    channel.setup_channel_provider

    expect(backend.commands_of('session.logout')).to be_empty
  end

  it 'leaves the inbox quarantined when the wrong account cannot be ended' do
    channel.update_provider_connection!({ 'connection' => 'close', 'error_code' => 'wrong_phone_number' })
    allow(backend).to receive(:logout).and_raise(Whatsapp::Session::Errors::ProviderUnavailable)

    expect { channel.provider_service.setup_channel_provider }
      .to raise_error(Whatsapp::Session::Errors::ProviderUnavailable)

    expect(channel.reload.provider_connection).to include('error_code' => 'wrong_phone_number')
    expect(backend.commands_of('session.connect')).to be_empty
  end

  # `Channel::Whatsapp` used to skip these by asking `respond_to?`, which the facade
  # makes true for every provider. The capability is what decides now, and an
  # unsupported one is skipped rather than raised: these run inside listeners, and a
  # listener that raises takes the event it was handling down with it.
  describe 'background synchronization a backend may not support' do
    before { allow(channel).to receive(:session_capabilities).and_return(%w[groups revoke]) }

    it 'skips marking a conversation unread' do
      message = create(:message, conversation: conversation, inbox: inbox, account: channel.account, source_id: '3EB0AAAA')

      expect { channel.unread_conversation(conversation.reload) }.not_to raise_error
      expect(backend.commands).to be_empty
      expect(message).to be_present
    end

    it 'skips read receipts, typing and presence' do
      message = create(:message, conversation: conversation, inbox: inbox, account: channel.account, source_id: '3EB0AAAA')

      channel.read_messages([message], conversation: conversation)
      channel.toggle_typing_status(Events::Types::CONVERSATION_TYPING_ON, conversation: conversation)
      channel.update_presence('available')

      expect(backend.commands).to be_empty
    end
  end

  # A receipt on WhatsApp is addressed by the message key, and in a group that key
  # includes who sent it: one command covering several senders cannot be acknowledged.
  it 'marks a group read one participant at a time' do
    group = create(:contact, account: channel.account, identifier: '120363041234567890@g.us', group_type: :group)
    group_inbox = create(:contact_inbox, contact: group, inbox: inbox, source_id: '120363041234567890')
    group_conversation = create(:conversation, contact: group, contact_inbox: group_inbox, inbox: inbox, account: channel.account)
    ana = create(:contact, account: channel.account, phone_number: '+5541999991111')
    bruno = create(:contact, account: channel.account, phone_number: '+5541999992222')
    messages = [
      create(:message, conversation: group_conversation, inbox: inbox, account: channel.account,
                       message_type: :incoming, sender: ana, source_id: '3EB0AAAA'),
      create(:message, conversation: group_conversation, inbox: inbox, account: channel.account,
                       message_type: :incoming, sender: bruno, source_id: '3EB0BBBB')
    ]

    channel.read_messages(messages, conversation: group_conversation)

    commands = backend.commands_of('message.mark_read')
    expect(commands.map { |command| command.sender&.id }).to contain_exactly('5541999991111', '5541999992222')
    expect(commands.flat_map(&:message_ids)).to contain_exactly('3EB0AAAA', '3EB0BBBB')
  end

  describe 'the group half' do
    subject(:facade) { channel.provider_service }

    let(:group_jid) { '120363041234567890@g.us' }

    around { |example| with_modified_env(WHATSAPP_GROUPS_ENABLED: 'true') { example.run } }

    it 'reports the group it created with the key the create service reads' do
      group = channel.create_group('Equipe', ['5541999990000@s.whatsapp.net'])

      expect(group[:id]).to end_with('@g.us')
      expect(backend.last_command.participants.map(&:id)).to eq(['5541999990000'])
    end

    it 'refuses a group setting it has no name for' do
      expect { channel.group_setting_update('120363041234567890@g.us', 'teleport', true) }
        .to raise_error(Whatsapp::Session::Errors::InvalidPayload)
    end

    it 'translates a group settings toggle into the contract name' do
      channel.group_member_add_mode('120363041234567890@g.us', 'all_member_add')

      expect(backend.last_command.setting).to eq('member_add_mode')
      expect(backend.last_command.value).to be(true)
    end

    it 'refuses to address a group by anything but a group jid' do
      expect { channel.group_leave('5541999990000@s.whatsapp.net') }
        .to raise_error(Whatsapp::Session::Errors::InvalidPayload)
    end

    # The dashboard hides the group panel when the switch is off, but the endpoints behind
    # it stay routable, so the switch has to hold where the calls land.
    it 'refuses every group operation while the installation has groups off' do
      with_modified_env WHATSAPP_GROUPS_ENABLED: 'false' do
        expect { channel.provider_service.group_leave(group_jid) }
          .to raise_error(Whatsapp::Session::Errors::NotSupported, /groups are disabled/)
        expect { channel.provider_service.create_group('Equipe', []) }
          .to raise_error(Whatsapp::Session::Errors::NotSupported, /groups are disabled/)
      end

      expect(backend.commands).to be_empty
    end

    it 'answers group creation in the shape Groups::CreateService reads' do
      result = facade.create_group('Equipe de Vendas', ['5541999990000@s.whatsapp.net'])

      expect(result).to eq({ id: '120363040000000001@g.us', subject: 'Equipe de Vendas' })
      expect(backend.last_command.subject).to eq('Equipe de Vendas')
    end

    it 'refuses a recipient that is not a group rather than addressing a person' do
      expect { facade.group_leave('5541999990000@s.whatsapp.net') }
        .to raise_error(Whatsapp::Session::Errors::InvalidPayload, /not a group/)
      expect(backend.commands).to be_empty
    end

    it 'translates the dashboard setting names into contract ones' do
      facade.group_setting_update(group_jid, 'restrict', true)

      expect(backend.last_command.setting).to eq('locked')
      expect(backend.last_command.value).to be(true)
    end

    it 'refuses a setting the contract has no name for' do
      expect { facade.group_setting_update(group_jid, 'whatever', true) }
        .to raise_error(Whatsapp::Session::Errors::InvalidPayload, /unknown group setting/)
    end

    # The dashboard endpoint builds the URL from what comes back, so anything but the
    # bare code renders a link with the host in it twice.
    it 'answers an invite with the code alone, and asks for a fresh one when revoking' do
      expect(facade.group_invite_code(group_jid)).to eq('FAKEINVITE0001')
      expect(backend.last_command.revoke).to be(false)

      expect(facade.revoke_group_invite(group_jid)).to eq('FAKEINVITE0001')
      expect(backend.last_command.revoke).to be(true)
    end

    # A provider can do groups without doing join requests: Uazapi is one. Asking its
    # backend anyway raises NotSupported on a routable endpoint.
    it 'answers join requests without the backend when the provider cannot approve them' do
      allow(channel).to receive(:session_capabilities).and_return(%w[groups])

      expect(channel.provider_service.group_join_requests(group_jid)).to eq([])
      expect { channel.provider_service.handle_group_join_requests(group_jid, ['5541999990000@s.whatsapp.net'], 'approve') }
        .to raise_error(Whatsapp::Session::Errors::NotSupported)
      expect(backend.commands).to be_empty
    end

    it 'renders a join request with the keys the dashboard already reads' do
      allow(backend).to receive(:group_join_requests).and_return(
        [{ 'party' => { 'phone' => '5541999990000', 'lid' => '182736451928374' }, 'requested_at' => 1_755_440_000 }]
      )

      expect(facade.group_join_requests(group_jid)).to eq(
        [{ 'jid' => '182736451928374@lid', 'phone_number' => '5541999990000', 'request_time' => 1_755_440_000 }]
      )
    end
  end

  # The schema types `calls` as an object, so a boolean makes the whole connect command
  # invalid and the session never pairs. `false` is not a value it accepts either, which
  # is why a backend without the capability sends nothing at all.
  it 'describes the call policy the way the contract types it' do
    channel.setup_channel_provider
    expect(backend.last_command.calls).to be_nil

    allow(channel).to receive(:session_capabilities).and_return(%w[calls])
    channel.provider_service.setup_channel_provider

    expect(backend.last_command.calls).to eq({ 'auto_reject' => true })
  end

  # The channel calls this from before_destroy and from convert_provider!, so it is a
  # teardown: the Baileys service answers it with DELETE /connections/<phone>. Only
  # disconnecting leaves the pairing alive on the provider under a session id Chatwoot
  # has just thrown away.
  it 'deletes the session when the inbox is torn down' do
    channel.disconnect_channel_provider

    expect(backend.commands_of('session.delete')).to be_present
  end

  # Chatwoot availability is online/offline/busy; the contract knows available and
  # unavailable. The Baileys service maps them, and this used to forward them raw.
  it 'maps account availability onto the two states the contract accepts' do
    channel.update_presence('online')
    expect(backend.last_command.state).to eq('available')

    channel.update_presence('busy')
    expect(backend.last_command.state).to eq('unavailable')
  end

  it 'subscribes to presence with an address, which is what the command carries' do
    facade.presence_subscribe(['182736451928374@lid'])

    expect(backend.last_command.party).to be_a(Whatsapp::Session::Model::Address)
    expect(backend.last_command.party.id).to eq('182736451928374')
  end

  # A close does not un-pair anything: the provider still holds the credentials, so the
  # next connect resumes. Losing the number to a transient disconnect cost a fresh scan.
  it 'resumes after a transient close, and asks for a QR after a logout' do
    channel.update_provider_connection!({ 'connection' => 'open', 'phone_number' => '5541988887777' })
    Whatsapp::Session::ConnectionStateWriter.new(channel).apply(
      Whatsapp::Session::Model::ConnectionState.new(connection: 'close', error: 'connection_closed')
    )
    channel.reload.provider_service.setup_channel_provider
    expect(backend.last_command.pairing).to eq('resume')

    Whatsapp::Session::ConnectionStateWriter.new(channel).apply(
      Whatsapp::Session::Model::ConnectionState.new(connection: 'close', error: 'logged_out')
    )
    channel.reload.provider_service.setup_channel_provider
    expect(backend.last_command.pairing).to eq('qr')
  end

  it 'connects with a QR when the session was never paired, and resumes afterwards' do
    channel.setup_channel_provider
    expect(backend.last_command.pairing).to eq('qr')

    channel.update_provider_connection!({ 'connection' => 'open', 'phone_number' => '5541988887777' })
    channel.provider_service.setup_channel_provider

    expect(backend.last_command.pairing).to eq('resume')
  end
end
