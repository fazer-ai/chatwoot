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
    expect(facade).to be_a(described_class)
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

    expect { channel.provider_service.setup_channel_provider }
      .to have_enqueued_job(Whatsapp::Session::PairingPollJob).with(channel, pairing: 'qr')
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

  describe 'the group half' do
    let(:group_jid) { '120363041234567890@g.us' }

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

    it 'asks for a fresh invite link when revoking the current one' do
      facade.group_invite_code(group_jid)
      expect(backend.last_command.revoke).to be(false)

      facade.revoke_group_invite(group_jid)
      expect(backend.last_command.revoke).to be(true)
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

  it 'connects with a QR when the session was never paired, and resumes afterwards' do
    channel.setup_channel_provider
    expect(backend.last_command.pairing).to eq('qr')

    channel.update_provider_connection!({ 'connection' => 'open', 'phone_number' => '5541988887777' })
    channel.provider_service.setup_channel_provider

    expect(backend.last_command.pairing).to eq('resume')
  end
end
