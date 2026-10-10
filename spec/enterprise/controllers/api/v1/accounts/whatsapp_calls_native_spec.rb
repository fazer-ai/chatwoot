require 'rails_helper'

# The calls API on a paired phone: the same endpoints and the same Call records as on a Cloud
# inbox, with the connector's commands where Meta's requests were.
RSpec.describe 'WhatsApp Calls API on a native inbox', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'native', account: account, validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:backend) { Whatsapp::Session::Backends::Fake.new(channel) }
  # The call command registry lives in Redis, which outlives an example.
  let(:command_suffix) { SecureRandom.hex(4) }
  let(:contact) { create(:contact, account: account, phone_number: '+5511988887777', identifier: '182736451928374@lid') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '182736451928374') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

  before do
    account.enable_features!('channel_voice')
    channel.update!(provider_config: channel.provider_config.merge('calling_enabled' => true))
    create(:inbox_member, user: agent, inbox: inbox)
    allow(Whatsapp::Session::Registry).to receive(:backend_for).and_return(backend)
    allow(Whatsapp::Connector::Client).to receive(:carries_calls?).and_return(true)
  end

  def incoming_call(id, status: 'ringing')
    create(:call, account: account, inbox: inbox, conversation: conversation, contact: contact,
                  provider: :whatsapp, direction: :incoming, status: status, provider_call_id: id)
  end

  def post_action(call, action, **params)
    post "/api/v1/accounts/#{account.id}/whatsapp_calls/#{call.id}/#{action}", params: params, headers: agent.create_new_auth_token
  end

  it 'answers with the browser\'s sdp and nothing before it' do
    call = incoming_call('CALLX3')

    post_action(call, :accept, sdp_answer: 'SDP-ANSWER-BROWSER')

    expect(response).to have_http_status(:ok)
    expect(call.reload.status).to eq('in_progress')
    expect(backend.commands.map(&:wire_type)).to eq(['call.accept'])
    expect(backend.last_command.to_h).to eq('call_id' => 'CALLX3', 'sdp' => 'SDP-ANSWER-BROWSER')
  end

  it 'tells the agent when the connector refused the answer at once, and leaves the call ringing' do
    call = incoming_call('CALLX7')
    allow(backend).to receive(:accept_call).and_return("cmd-accept-7-#{command_suffix}")
    Whatsapp::Session::CallCommands.failed("cmd-accept-7-#{command_suffix}")

    post_action(call, :accept, sdp_answer: 'SDP-ANSWER-BROWSER')

    expect(response).to have_http_status(:unprocessable_entity)
    expect(call.reload.status).to eq('ringing')
  end

  it 'refuses a ringing call naming its caller' do
    call = incoming_call('CALLX4')

    post_action(call, :reject)

    expect(response).to have_http_status(:ok)
    expect(call.reload.status).to eq('rejected')
    expect(backend.commands.map(&:to_h)).to eq([{ 'call_id' => 'CALLX4', 'from' => { 'kind' => 'lid', 'id' => '182736451928374' } }])
  end

  it 'hangs up once, and a second hang-up is no error' do
    call = incoming_call('CALLX6', status: 'in_progress')

    post_action(call, :terminate)
    expect(response).to have_http_status(:ok)
    post_action(call, :terminate)
    expect(response).to have_http_status(:ok)

    expect(call.reload.status).to eq('completed')
    expect(backend.commands_of('call.terminate').map(&:call_id)).to eq(['CALLX6'])
  end

  # An answer is the SDP itself; anything else is refused before the call changes.
  it 'refuses an answer that is not an sdp string, leaving the call ringing' do
    call = incoming_call('CALLX9')
    post_action(call, :accept, sdp_answer: { 'type' => 'answer' })

    expect(response).to have_http_status(:unprocessable_entity)
    expect(call.reload.status).to eq('ringing')
    expect(backend.commands_of('call.accept')).to be_empty
  end

  describe 'placing a call' do
    def initiate
      post "/api/v1/accounts/#{account.id}/whatsapp_calls/initiate",
           params: { conversation_id: conversation.display_id, sdp_offer: 'SDP-OFFER' }, headers: agent.create_new_auth_token
    end

    # The conversation is on the contact's LID, so the number comes from the connector.
    it 'rings the number behind the conversation and records the call id the connector chose' do
      initiate

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body).to include('call_id' => 'FAKECALL0001')
      command = backend.commands_of('call.start').sole
      expect(command.to_h).to eq('to' => { 'kind' => 'phone', 'id' => '5541999990000' }, 'sdp' => 'SDP-OFFER')
      expect(backend.commands_of('contact.resolve').first.party.id).to eq('182736451928374')
      expect(backend.idempotency_keys.sole).to be_present
      expect(Call.find_by(provider_call_id: 'FAKECALL0001'))
        .to have_attributes(direction: 'outgoing', status: 'ringing', conversation_id: conversation.id)
    end

    # A group's source id is no person to dial.
    it 'refuses to call a group, resolving nothing' do
      conversation.update!(group_type: :group)

      initiate

      expect(response).to have_http_status(:unprocessable_entity)
      expect(backend.commands_of('contact.resolve')).to be_empty
      expect(backend.commands_of('call.start')).to be_empty
    end

    # The contact panel hands over the contact's own number, which the connector need not know yet.
    it 'rings a contact from the contact panel on the contact\'s number' do
      fresh = create(:contact, account: account, phone_number: '+5511977776666')
      post "/api/v1/accounts/#{account.id}/whatsapp_calls/initiate",
           params: { inbox_id: inbox.id, contact_id: fresh.id, sdp_offer: 'SDP-OFFER' }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(backend.commands_of('call.start').sole.to.id).to eq('5511977776666')
    end

    # The fake connector pairs these digits, as a LID, with another phone.
    it 'rings the contact\'s number even when its digits are a LID the connector knows' do
      collision = create(:contact, account: account, phone_number: '+182736451928374')
      post "/api/v1/accounts/#{account.id}/whatsapp_calls/initiate",
           params: { inbox_id: inbox.id, contact_id: collision.id, sdp_offer: 'SDP-OFFER' }, headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(backend.commands_of('call.start').sole.to.id).to eq('182736451928374')
    end

    # A pickup that beat the record of the call it answers is applied as soon as the record exists.
    it 'connects a call picked up before this request recorded it' do
      allow(backend).to receive(:start_call).and_wrap_original do |original, *args, **kwargs|
        call_id = original.call(*args, **kwargs)
        answered = Whatsapp::Session::Model::Events::CallAnswered.new(call_id: call_id, sdp: 'SDP-EARLY')
        Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, Whatsapp::Session::Model::Event.build(answered))
        call_id
      end

      # Applied a moment later, once the tab that placed the call knows it.
      expect { initiate }.to have_enqueued_job(Whatsapp::ConnectorCallReconcileJob)
      expect(Call.find_by(provider_call_id: 'FAKECALL0001').meta['sdp_answer']).to be_nil

      perform_enqueued_jobs(only: Whatsapp::ConnectorCallReconcileJob)
      expect(Call.find_by(provider_call_id: 'FAKECALL0001').meta['sdp_answer']).to eq('SDP-EARLY')
    end

    # The agent hangs up before the reconciliation applies a pickup that beat the record.
    it 'ends as answered a call picked up before it was recorded, when the agent hangs up first' do
      allow(backend).to receive(:start_call).and_wrap_original do |original, *args, **kwargs|
        call_id = original.call(*args, **kwargs)
        answered = Whatsapp::Session::Model::Events::CallAnswered.new(call_id: call_id, sdp: 'SDP-EARLY')
        Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, Whatsapp::Session::Model::Event.build(answered))
        call_id
      end
      initiate
      placed = Call.find_by(provider_call_id: 'FAKECALL0001')

      post_action(placed, :terminate)

      expect(placed.reload).to have_attributes(status: 'completed', end_reason: 'agent_hangup')
      expect(placed.meta['sdp_answer']).to eq('SDP-EARLY')
      expect(placed.duration_seconds).not_to be_nil
    end

    # The callee refused before the call was recorded, and the agent hangs up before the
    # reconciliation applies that end: the call is the one the callee ended.
    it 'ends as the callee ended it a call refused before it was recorded, when the agent hangs up first' do
      allow(backend).to receive(:start_call).and_wrap_original do |original, *args, **kwargs|
        call_id = original.call(*args, **kwargs)
        ended = Whatsapp::Session::Model::Events::CallTerminate.new(call_id: call_id, from: nil, reason: 'rejected')
        Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, Whatsapp::Session::Model::Event.build(ended))
        call_id
      end
      initiate
      placed = Call.find_by(provider_call_id: 'FAKECALL0001')

      post_action(placed, :terminate)

      expect(placed.reload.end_reason).to eq('rejected')
      expect(backend.commands_of('call.terminate')).to be_empty
    end

    it 'tells the agent when the connector refuses, and records no call' do
      allow(backend).to receive(:start_call).and_raise(Whatsapp::Session::Errors::NotSupported, 'calls are not carried here')
      broadcasts = []
      allow(ActionCable.server).to receive(:broadcast) { |_, payload| broadcasts << payload[:event] }

      initiate

      expect(response).to have_http_status(:unprocessable_entity)
      expect(Call.count).to eq(0)
      expect(broadcasts).not_to include('voice_call.outbound_connected', 'voice_call.outbound_accepted')
    end
  end
end
