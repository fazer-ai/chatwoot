require 'rails_helper'

# An inbox whose calls a voice agent takes: the offer is filed as a Call and answered with the
# agent's media stream instead of ringing the agents' screens, and handed back to them when the
# stream does not open.
RSpec.describe Whatsapp::ConnectorAiCallService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'native', phone_number: '+5541988887777',
                              validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:backend) { Whatsapp::Session::Backends::Fake.new(channel) }
  let(:model) { Whatsapp::Session::Model }
  # The call command registry lives in Redis, which outlives an example.
  let(:command_suffix) { SecureRandom.hex(4) }
  let(:caller_party) { model::Party.new(phone: '5511988887777', lid: '182736451928374', push_name: 'Ana Souza') }
  let(:sdp_offer) { "v=0\r\no=- 1 1 IN IP4 0.0.0.0\r\n" }
  let(:broadcasts) { [] }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:stream_base) { 'wss://agents.example.com/api/v1/voice/stream/route-token?k=secret' }

  before do
    account.enable_features!('channel_voice')
    channel.update!(provider_config: channel.provider_config.merge(
      'calling_enabled' => true, 'ai_voice' => { 'enabled' => true, 'stream_url' => stream_base }
    ))
    create(:inbox_member, user: agent, inbox: inbox)
    allow(Whatsapp::Session::Registry).to receive(:backend_for).and_return(backend)
    allow(ActionCable.server).to receive(:broadcast) { |stream, payload| broadcasts << [stream, payload] }
  end

  def dispatch(payload)
    Whatsapp::Session::Inbound::Dispatcher.dispatch(Channel::Whatsapp.find(channel.id), model::Event.build(payload))
  end

  def offer(call_id, sdp: sdp_offer)
    dispatch(model::Events::CallOffer.new(call_id: call_id, from: caller_party, video: false, timestamp: 1_755_440_000_123, sdp: sdp))
  end

  def accepts = backend.commands_of('call.accept')

  def events = broadcasts.map(&:last).pluck(:event)

  def query_of(url) = URI.decode_www_form(URI.parse(url).query).to_h

  it 'answers the call with the voice agent instead of ringing the agents' do
    expect(offer('CALLAI1')).to eq(:handled)

    call = Call.find_by!(provider_call_id: 'CALLAI1')
    expect(call).to have_attributes(status: 'in_progress', direction: 'incoming', accepted_by_agent_id: nil)
    expect(call.started_at).to be_present
    expect(call.meta).to include('ai_voice' => true)
    expect(events).not_to include('voice_call.incoming')
    expect(backend.commands_of('call.reject')).to be_empty
  end

  # The call is recorded ringing before the voice agent answers it, and its message would put a
  # card on the agents' screens for that moment.
  it 'records the call as the voice agent\'s from its first message' do
    recorded = nil
    allow(Voice::InboundCallBuilder).to receive(:perform!).and_wrap_original do |original, **kwargs|
      original.call(**kwargs).tap { |call| recorded = call.message.push_event_data[:call] }
    end

    offer('CALLAI1')

    expect(recorded).to include(status: 'ringing', voice_agent: true)
  end

  # The call's ringing message put a card on the agents' screens; an answer takes it down.
  it 'announces the call as answered to the account' do
    offer('CALLAI1')

    accepted = broadcasts.select { |_, payload| payload[:event] == 'voice_call.accepted' }
    expect(accepted.map(&:first)).to eq(["account_#{account.id}"])
    expect(accepted.first.last[:data]).to include(call_id: 'CALLAI1', provider: 'whatsapp')
  end

  # The call's message offers to join it while it rings, so somebody can take it first.
  it 'leaves to the agent a call joined before the voice agent answers' do
    allow(described_class).to receive(:stream_url).and_wrap_original do |original, *args, **kwargs|
      Call.find(kwargs[:call].id).update!(status: 'in_progress', accepted_by_agent_id: agent.id)
      original.call(*args, **kwargs)
    end

    offer('CALLAI1')

    expect(accepts).to be_empty
    expect(Call.find_by!(provider_call_id: 'CALLAI1')).to have_attributes(accepted_by_agent_id: agent.id)
    expect(Call.find_by!(provider_call_id: 'CALLAI1').meta).not_to include('ai_voice')
    expect(events).not_to include('voice_call.incoming')
  end

  it 'answers with the stored stream URL, naming the call and its thread' do
    offer('CALLAI1')
    call = Call.find_by!(provider_call_id: 'CALLAI1')

    expect(accepts.size).to eq(1)
    expect(accepts.first.sdp).to be_nil
    url = accepts.first.stream['url']
    expect(url).to start_with('wss://agents.example.com/api/v1/voice/stream/route-token?')
    expect(url.count('?')).to eq(1)
    expect(query_of(url)).to eq('k' => 'secret', 'account_id' => account.id.to_s, 'inbox_id' => inbox.id.to_s,
                                'conversation_id' => call.conversation.display_id.to_s, 'direction' => 'inbound',
                                'call_id' => 'CALLAI1')
  end

  it 'puts the call on the thread as answered' do
    offer('CALLAI1')

    call = Call.find_by!(provider_call_id: 'CALLAI1')
    expect(call.conversation.additional_attributes['call_status']).to eq(call.display_status)
    expect(call.message).to be_present
  end

  # Whoever the conversation is with, the voice agent takes the call: a person who wants to
  # talk calls the contact.
  it 'answers whatever state the contact\'s conversation is in' do
    offer('CALLAI1')
    conversation = Call.find_by!(provider_call_id: 'CALLAI1').conversation

    conversation.update!(assignee: agent)
    offer('CALLAI2')
    conversation.update!(status: :resolved)
    offer('CALLAI3')

    expect(accepts.map(&:call_id)).to eq(%w[CALLAI1 CALLAI2 CALLAI3])
    expect(Call.where(provider_call_id: %w[CALLAI1 CALLAI2 CALLAI3]).pluck(:status).uniq).to eq(['in_progress'])
    expect(events).not_to include('voice_call.incoming')
  end

  # The design before this one derived the stream from the inbox's Agent Bot: a bot pointing at
  # fazer.ai agents is not a voice agent, and one that is not does not stand in its way.
  it 'takes the stream from the inbox, whatever agent bot it has' do
    bot = create(:agent_bot, account: account, outgoing_url: 'https://agents.example.com/api/v1/chatwoot/webhook/tok-bot')
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)

    offer('CALLAI1')
    channel.update!(provider_config: channel.provider_config.merge('ai_voice' => { 'enabled' => false }))
    offer('CALLAI2')

    expect(accepts.map(&:call_id)).to eq(['CALLAI1'])
    expect(accepts.first.stream['url']).to start_with('wss://agents.example.com/api/v1/voice/stream/route-token?')
    expect(Call.find_by!(provider_call_id: 'CALLAI2').status).to eq('ringing')
  end

  it 'answers a redelivered offer once' do
    offer('CALLAI1')
    offer('CALLAI1')

    expect(Call.where(provider_call_id: 'CALLAI1').count).to eq(1)
    expect(accepts.size).to eq(1)
  end

  it 'rings the agents as before once the voice agent is switched off' do
    channel.update!(provider_config: channel.provider_config.merge('ai_voice' => { 'enabled' => false, 'stream_url' => stream_base }))

    offer('CALLAI2')

    expect(Call.find_by!(provider_call_id: 'CALLAI2').status).to eq('ringing')
    expect(accepts).to be_empty
    expect(events).to include('voice_call.incoming')
  end

  # The connector offers a call without `sdp` when it could not build the browser's half,
  # and a stream needs none.
  it 'answers a call offered without a browser\'s half' do
    expect(offer('CALLAI1', sdp: nil)).to eq(:handled)

    expect(accepts.map(&:call_id)).to eq(['CALLAI1'])
    expect(Call.find_by!(provider_call_id: 'CALLAI1').status).to eq('in_progress')
  end

  it 'leaves a call offered without a browser\'s half as the activity line with the voice agent off' do
    channel.update!(provider_config: channel.provider_config.merge('ai_voice' => { 'enabled' => false, 'stream_url' => stream_base }))

    offer('CALLAI1', sdp: nil)

    expect(Call.where(provider_call_id: 'CALLAI1')).to be_empty
    expect(accepts).to be_empty
  end

  it 'rings the agents for a stored URL nobody switched on' do
    channel.update!(provider_config: channel.provider_config.merge('ai_voice' => { 'stream_url' => stream_base }))

    offer('CALLAI2')

    expect(accepts).to be_empty
    expect(events).to include('voice_call.incoming')
  end

  # The connector answers `invalid_payload` when it cannot open the stream, and the call goes
  # on ringing on the caller's phone: the agents are rung for it, as if no voice agent was set.
  describe 'a stream the connector could not open' do
    before do
      allow(backend).to receive(:accept_call).and_wrap_original do |original, command|
        original.call(command)
        "cmd-ai-#{command.call_id}-#{command_suffix}"
      end
    end

    def failed(call_id)
      dispatch(model::Events::CommandFailed.new(command_id: "cmd-ai-#{call_id}-#{command_suffix}", command_type: 'call.accept',
                                                message_id: nil,
                                                error: model::WireError.new(code: 'invalid_payload', message: 'stream unreachable')))
    end

    it 'puts the call back to ringing for the agents, without refusing it' do
      offer('CALLAI1')

      expect(failed('CALLAI1')).to eq(:handled)

      call = Call.find_by!(provider_call_id: 'CALLAI1')
      expect(call).to have_attributes(status: 'ringing', started_at: nil)
      expect(call.meta.slice('rung', 'ai_voice', 'voice_agent')).to eq('rung' => true)
      expect(call.message.reload.push_event_data[:call]).to include(status: 'ringing', voice_agent: false)
      incoming = broadcasts.find { |_, payload| payload[:event] == 'voice_call.incoming' }
      expect(incoming.first).to eq(agent.pubsub_token)
      expect(incoming.last[:data]).to include(call_id: 'CALLAI1', sdp_offer: sdp_offer)
      expect(backend.commands_of('call.reject')).to be_empty
    end

    # The expiry scheduled with the offer may have run while the voice agent had the call.
    it 'schedules the ring expiry again for the call handed back' do
      offer('CALLAI1')
      call = Call.find_by!(provider_call_id: 'CALLAI1')

      expect { failed('CALLAI1') }.to have_enqueued_job(Whatsapp::ConnectorCallExpireJob).with(call.id)
    end

    # Nobody can join it from the browser: it is closed here and goes on ringing on the phone.
    it 'closes, without refusing, a call offered without a browser\'s half' do
      offer('CALLAI1', sdp: nil)

      failed('CALLAI1')

      expect(Call.find_by!(provider_call_id: 'CALLAI1')).to have_attributes(status: 'failed', end_reason: 'accept_failed')
      expect(events).not_to include('voice_call.incoming')
      expect(backend.commands_of('call.reject')).to be_empty
    end

    it 'closes, without refusing, one whose failure arrived before the answer was recorded' do
      failed('CALLAI1')

      offer('CALLAI1', sdp: nil)

      expect(Call.find_by!(provider_call_id: 'CALLAI1')).to have_attributes(status: 'failed', end_reason: 'accept_failed')
      expect(events).not_to include('voice_call.incoming')
      expect(backend.commands_of('call.reject')).to be_empty
    end

    it 'ends the call handed back as unanswered when the caller hangs up' do
      offer('CALLAI1')
      failed('CALLAI1')

      dispatch(model::Events::CallTerminate.new(call_id: 'CALLAI1', from: caller_party, reason: 'hangup'))

      expect(Call.find_by!(provider_call_id: 'CALLAI1').status).to eq('no_answer')
    end

    it 'rings the agents once for the failure delivered again' do
      offer('CALLAI1')
      failed('CALLAI1')
      failed('CALLAI1')

      expect(events.count('voice_call.incoming')).to eq(1)
    end

    # Handed to the agents, and the failure delivered again because letting go of it failed.
    it 'does not close the call handed to the agents on the failure delivered again' do
      offer('CALLAI1')
      allow(Whatsapp::Session::CallCommands).to receive(:settled).and_raise(Redis::CannotConnectError, 'down')
      expect { failed('CALLAI1') }.to raise_error(Redis::CannotConnectError)
      allow(Whatsapp::Session::CallCommands).to receive(:settled).and_call_original

      expect(failed('CALLAI1')).to eq(:handled)

      expect(Call.find_by!(provider_call_id: 'CALLAI1').status).to eq('ringing')
      expect(events.count('voice_call.incoming')).to eq(1)
      expect(backend.commands_of('call.reject')).to be_empty
    end

    # Ended between the failure finding the call and taking its lock.
    it 'does not ring for a call that ended while the failure was being applied' do
      offer('CALLAI1')
      allow(Whatsapp::ConnectorCallService).to receive(:new).and_wrap_original do |original, **kwargs|
        original.call(**kwargs).tap do |service|
          allow(service).to receive(:find_call).and_wrap_original do |find, *args|
            find.call(*args).tap { |found| Call.find(found.id).update!(status: 'completed') }
          end
        end
      end

      failed('CALLAI1')

      expect(Call.find_by!(provider_call_id: 'CALLAI1').status).to eq('completed')
      expect(events).not_to include('voice_call.incoming')
    end

    it 'leaves alone a call that ended before the failure arrived' do
      offer('CALLAI1')
      dispatch(model::Events::CallTerminate.new(call_id: 'CALLAI1', from: caller_party, reason: 'hangup'))

      failed('CALLAI1')

      expect(Call.find_by!(provider_call_id: 'CALLAI1').status).not_to eq('ringing')
      expect(events).not_to include('voice_call.incoming')
    end

    # The failure read before the request that published the answer wrote down its call.
    it 'rings the agents at once for a failure that arrived before the answer was recorded' do
      failed('CALLAI1')

      offer('CALLAI1')

      call = Call.find_by!(provider_call_id: 'CALLAI1')
      expect(call).to have_attributes(status: 'ringing', started_at: nil)
      expect(call.meta).not_to include('voice_agent')
      expect(events).to include('voice_call.incoming')
    end

    it 'still closes as failed a browser answer that fails on an inbox with a voice agent' do
      call = Call.create!(account: account, inbox: inbox, conversation: create(:conversation, inbox: inbox, account: account),
                          contact: create(:contact, account: account), provider: :whatsapp, direction: :incoming,
                          status: 'in_progress', provider_call_id: 'CALLBR1', started_at: Time.current, meta: {})
      Whatsapp::Session::CallCommands.remember("cmd-ai-CALLBR1-#{command_suffix}", 'CALLBR1')

      failed('CALLBR1')

      expect(call.reload.status).to eq('failed')
    end
  end

  # The connector may lose a call's end along with the instance that carried it, and no browser
  # would notice: a call still going past the longest a voice agent keeps one is ended here.
  describe 'a voice agent\'s call whose end never arrived' do
    def expire(call_id) = Whatsapp::ConnectorCallExpireJob.perform_now(Call.find_by!(provider_call_id: call_id).id)

    it 'schedules its expiry past the longest a voice agent keeps a call' do
      expect { offer('CALLAI1') }.to have_enqueued_job(Whatsapp::ConnectorCallExpireJob)
        .with(kind_of(Integer)).at(a_value_within(5.seconds).of(70.minutes.from_now))
    end

    it 'ends it once that long has passed' do
      offer('CALLAI1')

      travel 70.minutes + 1.second do
        expire('CALLAI1')
      end

      expect(Call.find_by!(provider_call_id: 'CALLAI1')).to have_attributes(status: 'completed', end_reason: 'expired')
      expect(Call.find_by!(provider_call_id: 'CALLAI1').duration_seconds).to be >= 4200
    end

    it 'leaves it alone before then' do
      offer('CALLAI1')

      travel 69.minutes do
        expire('CALLAI1')
      end

      expect(Call.find_by!(provider_call_id: 'CALLAI1').status).to eq('in_progress')
    end
  end

  # The stream that ended is the voice agent's doing or the socket's, and the record says which.
  it 'keeps the connector\'s reason for how the voice agent\'s call ended' do
    offer('CALLAI1')
    offer('CALLAI2')

    dispatch(model::Events::CallTerminate.new(call_id: 'CALLAI1', from: nil, reason: 'stream_hangup'))
    dispatch(model::Events::CallTerminate.new(call_id: 'CALLAI2', from: nil, reason: 'stream_lost'))

    expect(Call.find_by!(provider_call_id: 'CALLAI1')).to have_attributes(status: 'completed', end_reason: 'stream_hangup')
    expect(Call.find_by!(provider_call_id: 'CALLAI2')).to have_attributes(status: 'completed', end_reason: 'stream_lost')
  end
end
