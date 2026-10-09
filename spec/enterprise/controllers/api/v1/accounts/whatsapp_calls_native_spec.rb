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
  let(:contact) { create(:contact, account: account, phone_number: '+5511988887777', identifier: '182736451928374@lid') }
  let(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '182736451928374') }
  let(:conversation) { create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox) }

  before do
    account.enable_features!('channel_voice')
    channel.update!(provider_config: channel.provider_config.merge('calling_enabled' => true))
    create(:inbox_member, user: agent, inbox: inbox)
    allow(Whatsapp::Session::Registry).to receive(:backend_for).and_return(backend)
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
      expect(backend.commands_of('contact.resolve').sole.party.id).to eq('182736451928374')
      expect(backend.idempotency_keys.sole).to be_present
      expect(Call.find_by(provider_call_id: 'FAKECALL0001'))
        .to have_attributes(direction: 'outgoing', status: 'ringing', conversation_id: conversation.id)
    end

    # A pickup that beat the record of the call it answers is applied as soon as the record exists.
    it 'connects a call picked up before this request recorded it' do
      allow(backend).to receive(:start_call).and_wrap_original do |original, *args, **kwargs|
        call_id = original.call(*args, **kwargs)
        answered = Whatsapp::Session::Model::Events::CallAnswered.new(call_id: call_id, sdp: 'SDP-EARLY')
        Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, Whatsapp::Session::Model::Event.build(answered))
        call_id
      end

      initiate

      expect(response).to have_http_status(:ok)
      expect(Call.find_by(provider_call_id: 'FAKECALL0001').meta['sdp_answer']).to eq('SDP-EARLY')
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
