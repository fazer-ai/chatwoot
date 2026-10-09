require 'rails_helper'

# The connector's call events, end to end through the dispatcher: the same records and
# broadcasts the Cloud path produces for Meta's webhooks, from the session layer's events.
RSpec.describe Whatsapp::ConnectorCallService do
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

  before do
    account.enable_features!('channel_voice')
    channel.update!(provider_config: channel.provider_config.merge('calling_enabled' => true))
    allow(Whatsapp::Session::Registry).to receive(:backend_for).and_return(backend)
    allow(ActionCable.server).to receive(:broadcast) { |stream, payload| broadcasts << [stream, payload] }
  end

  def dispatch(payload, **attributes)
    Whatsapp::Session::Inbound::Dispatcher.dispatch(Channel::Whatsapp.find(channel.id), model::Event.build(payload, **attributes))
  end

  def offer(call_id, sdp: sdp_offer, video: false)
    dispatch(model::Events::CallOffer.new(call_id: call_id, from: caller_party, video: video, timestamp: 1_755_440_000_123, sdp: sdp))
  end

  def events_named(name)
    broadcasts.map(&:last).select { |payload| payload[:event] == name }
  end

  def call_lines
    inbox.messages.where(message_type: :activity).where("content LIKE '%WhatsApp%'")
  end

  describe 'an offer the browser can answer' do
    # Rung on the agents' own streams, as on the Cloud path, so the inbox needs one.
    let(:agent) { create(:user, account: account, role: :agent) }

    before { create(:inbox_member, user: agent, inbox: inbox) }

    it 'rings as a Call on the caller\'s thread, with no activity line beside it' do
      expect(offer('CALLX1')).to eq(:handled)

      call = Call.find_by!(provider_call_id: 'CALLX1')
      expect(call).to have_attributes(inbox_id: inbox.id, direction: 'incoming', status: 'ringing', provider: 'whatsapp')
      expect(call.meta['sdp_offer']).to eq(sdp_offer)
      expect(call.conversation.contact_inbox.source_id).to eq('182736451928374')
      expect(call.message).to be_present
      expect(call_lines).to be_empty
      expect(backend.commands).to be_empty
    end

    it 'rings the inbox\'s agents with the offer for the browser' do
      offer('CALLX1')

      incoming = events_named('voice_call.incoming')
      expect(incoming.size).to eq(1)
      expect(broadcasts.find { |_, payload| payload[:event] == 'voice_call.incoming' }.first).to eq(agent.pubsub_token)
      expect(incoming.first[:data]).to include(call_id: 'CALLX1', sdp_offer: sdp_offer, provider: 'whatsapp')
    end

    # The same thread a message from this contact lands on, not a second contact.
    # Refusing it from the ringing widget names that address, whatever the contact becomes.
    it 'keeps the address the call came from' do
      offer('CALLX1')

      expect(Call.find_by!(provider_call_id: 'CALLX1').meta['caller_address']).to eq('kind' => 'lid', 'id' => '182736451928374')
    end

    it 'files the call where the contact\'s messages are' do
      offer('CALLX1')
      offer('CALLX2')

      expect(Call.where(provider_call_id: %w[CALLX1 CALLX2]).distinct.pluck(:contact_id).size).to eq(1)
      expect(inbox.contact_inboxes.count).to eq(1)
    end

    # Redelivered after an agent took it: ringing again would bring back the card the
    # accept removed from every other agent's screen.
    it 'does not ring again for an offer it already rang' do
      offer('CALLX1')
      Call.find_by!(provider_call_id: 'CALLX1').update!(status: 'in_progress')

      offer('CALLX1')

      expect(events_named('voice_call.incoming').size).to eq(1)
    end

    it 'does not ring again for an offer still ringing that it already rang' do
      offer('CALLX1')
      offer('CALLX1')

      expect(events_named('voice_call.incoming').size).to eq(1)
    end

    # The call is recorded before the agents are rung, and the stream redelivers an offer
    # whose handling failed in between.
    it 'rings for an offer redelivered after it failed before ringing anyone' do
      ringing = 0
      allow(ActionCable.server).to receive(:broadcast) do |stream, payload|
        raise Redis::CannotConnectError, 'down' if payload[:event] == 'voice_call.incoming' && (ringing += 1) == 1

        broadcasts << [stream, payload]
      end
      expect { offer('CALLX1') }.to raise_error(Redis::CannotConnectError)

      offer('CALLX1')

      expect(Call.where(provider_call_id: 'CALLX1').count).to eq(1)
      expect(events_named('voice_call.incoming').size).to eq(1)
    end

    it 'is one Call however many times the offer arrives' do
      offer('CALLX1')
      offer('CALLX1')

      expect(Call.where(provider_call_id: 'CALLX1').count).to eq(1)
    end
  end

  describe 'an offer the browser cannot answer' do
    it 'is the activity line it always was when it carries no sdp' do
      expect(offer('CALLX9', sdp: nil)).to eq(:handled)

      expect(Call.where(provider_call_id: 'CALLX9')).to be_empty
      expect(events_named('voice_call.incoming')).to be_empty
      expect(call_lines.count).to eq(1)
    end

    it 'is the activity line on an inbox with calling off' do
      channel.update!(provider_config: channel.provider_config.merge('calling_enabled' => false))

      expect(offer('CALLX2')).to eq(:handled)
      expect(Call.where(provider_call_id: 'CALLX2')).to be_empty
      expect(call_lines.count).to eq(1)
    end

    it 'is the activity line on an account without voice' do
      account.disable_features!('channel_voice')

      expect(offer('CALLX2')).to eq(:handled)
      expect(Call.where(provider_call_id: 'CALLX2')).to be_empty
      expect(call_lines.count).to eq(1)
    end

    # The connector lets every call ring on an inbox with calling on, so that the inbox can
    # still place calls; refusing the incoming ones is done here, as the Cloud path does.
    # A video call carries no sdp, and with calling on the connector lets it ring too.
    it 'refuses any call, a video one included, when incoming calls are off' do
      channel.update!(provider_config: channel.provider_config.merge('inbound_calls_enabled' => false))

      offer('CALLV1', sdp: nil, video: true)

      expect(backend.commands.map(&:to_h)).to eq([{ 'call_id' => 'CALLV1', 'from' => { 'kind' => 'lid', 'id' => '182736451928374' } }])
      expect(call_lines.count).to eq(1)
    end

    # A blocked contact is filed nowhere, and the inbox takes no calls: the call is refused
    # all the same, or it would go on ringing on the paired phone.
    it 'refuses a blocked contact\'s call too, filing nothing' do
      channel.update!(provider_config: channel.provider_config.merge('inbound_calls_enabled' => false))
      offer('CALLB0')
      inbox.contacts.find_by(identifier: '182736451928374@lid').update!(blocked: true)

      offer('CALLB1')

      expect(backend.commands_of('call.reject').map(&:call_id)).to eq(%w[CALLB0 CALLB1])
      expect(call_lines.count).to eq(1)
    end

    it 'is refused by name, with the line, when incoming calls are off' do
      channel.update!(provider_config: channel.provider_config.merge('inbound_calls_enabled' => false))

      expect(offer('CALLX4')).to eq(:handled)

      expect(backend.commands.map(&:wire_type)).to eq(['call.reject'])
      expect(backend.last_command.to_h).to eq('call_id' => 'CALLX4', 'from' => { 'kind' => 'lid', 'id' => '182736451928374' })
      expect(Call.where(provider_call_id: 'CALLX4')).to be_empty
      expect(events_named('voice_call.incoming')).to be_empty
      expect(call_lines.count).to eq(1)
    end
  end

  describe 'a placed call being answered' do
    let(:conversation) { create(:conversation, inbox: inbox, account: account) }
    let!(:call) do
      Call.create!(account: account, inbox: inbox, conversation: conversation, contact: conversation.contact, provider: :whatsapp,
                   direction: :outgoing, status: 'ringing', provider_call_id: 'CALLOUT2', meta: { 'sdp_offer' => 'SDP-OFFER' })
    end

    it 'hands the browser the connector\'s answer and marks the call as picked up' do
      expect(dispatch(model::Events::CallAnswered.new(call_id: 'CALLOUT2', sdp: 'SDP-ANSWER-CONNECTOR'))).to eq(:handled)

      expect(call.reload.meta['sdp_answer']).to eq('SDP-ANSWER-CONNECTOR')
      expect(call.status).to eq('in_progress')
      expect(events_named('voice_call.outbound_connected').map { |p| p[:data][:sdp_answer] }).to eq(['SDP-ANSWER-CONNECTOR'])
      expect(events_named('voice_call.outbound_accepted').size).to eq(1)
    end

    # Only a call this inbox placed can be picked up; an answer naming a received one is not
    # an answer to anything the browser offered.
    it 'leaves a received call alone' do
      received = Call.create!(account: account, inbox: inbox, conversation: conversation, contact: conversation.contact,
                              provider: :whatsapp, direction: :incoming, status: 'ringing', provider_call_id: 'CALLX10', meta: {})

      dispatch(model::Events::CallAnswered.new(call_id: 'CALLX10', sdp: 'x'))

      expect(received.reload.status).to eq('ringing')
      expect(received.meta['sdp_answer']).to be_nil
      expect(broadcasts).to be_empty
    end

    it 'does nothing for a call it does not know' do
      expect { dispatch(model::Events::CallAnswered.new(call_id: 'NAOEXISTE', sdp: 'x')) }.not_to change(Call, :count)

      expect(call.reload.meta['sdp_answer']).to be_nil
      expect(broadcasts).to be_empty
    end

    # `call.start` answers once the phone rings, and the record is written after that; a
    # quick pickup, or a quick refusal, arrives in between and is not delivered again.
    it 'applies what arrived for a placed call before it was recorded, once it is' do
      dispatch(model::Events::CallAnswered.new(call_id: 'CALLOUT9', sdp: 'SDP-EARLY'))
      dispatch(model::Events::CallTerminate.new(call_id: 'CALLOUT9', from: caller_party, reason: nil))
      late = Call.create!(account: account, inbox: inbox, conversation: conversation, contact: conversation.contact, provider: :whatsapp,
                          direction: :outgoing, status: 'ringing', provider_call_id: 'CALLOUT9', meta: {})

      described_class.new(inbox: inbox).reconcile(late)

      expect(late.reload.meta['sdp_answer']).to eq('SDP-EARLY')
      expect(late.status).to eq('completed')
      expect(events_named('voice_call.outbound_connected').size).to eq(1)
      expect(events_named('voice_call.ended').size).to eq(1)

      described_class.new(inbox: inbox).reconcile(late)
      expect(events_named('voice_call.outbound_connected').size).to eq(1)
      %w[answered terminate].each do |kind|
        key = format(Redis::Alfred::WHATSAPP_CONNECTOR_CALL_PENDING, inbox_id: inbox.id, call_id: 'CALLOUT9', kind: kind)
        expect(Redis::Alfred.get(key)).to be_nil
      end
    end
  end

  describe 'what arrives for a placed call before it is recorded' do
    # The job that applies it runs from a queue, which can be backed up well past the
    # request that records the call.
    it 'is kept for as long as a backed-up queue can hold the job that applies it' do
      call_id = "CALLOUT7#{command_suffix}"
      dispatch(model::Events::CallAnswered.new(call_id: call_id, sdp: 'SDP-EARLY'))
      dispatch(model::Events::CallTerminate.new(call_id: call_id, from: caller_party, reason: nil))

      %w[answered terminate].each do |kind|
        key = format(Redis::Alfred::WHATSAPP_CONNECTOR_CALL_PENDING, inbox_id: inbox.id, call_id: call_id, kind: kind)
        expect(Redis::Alfred.ttl(key)).to be > 1.hour.to_i
      end
    end
  end

  describe 'a pickup kept for a call recorded since' do
    let(:conversation) { create(:conversation, inbox: inbox, account: account) }

    # The pickup arrived before the record; the end arrived after it and before the
    # reconciliation. The end is of an answered call.
    it 'is applied before an end that arrives first' do
      dispatch(model::Events::CallAnswered.new(call_id: 'CALLOUT8', sdp: 'SDP-EARLY'))
      late = Call.create!(account: account, inbox: inbox, conversation: conversation, contact: conversation.contact, provider: :whatsapp,
                          direction: :outgoing, status: 'ringing', provider_call_id: 'CALLOUT8', meta: {})

      dispatch(model::Events::CallTerminate.new(call_id: 'CALLOUT8', from: caller_party, reason: nil))

      expect(late.reload.status).to eq('completed')
      expect(late.meta['sdp_answer']).to eq('SDP-EARLY')
    end

    # The job is retried when the database fails it, and the retry still has what to apply.
    it 'keeps what it applies until the call is written' do
      call_id = "CALLOUT5#{command_suffix}"
      dispatch(model::Events::CallAnswered.new(call_id: call_id, sdp: 'SDP-EARLY'))
      dispatch(model::Events::CallTerminate.new(call_id: call_id, from: caller_party, reason: nil))
      late = Call.create!(account: account, inbox: inbox, conversation: conversation, contact: conversation.contact, provider: :whatsapp,
                          direction: :outgoing, status: 'ringing', provider_call_id: call_id, meta: {})
      database_down = true
      allow_any_instance_of(Call).to receive(:update!).and_wrap_original do |original, *args, **kwargs| # rubocop:disable RSpec/AnyInstance
        raise ActiveRecord::StatementInvalid, 'connection lost' if database_down

        original.call(*args, **kwargs)
      end

      expect { described_class.new(inbox: inbox).reconcile(late) }.to raise_error(ActiveRecord::StatementInvalid)

      database_down = false
      described_class.new(inbox: inbox).reconcile(Call.find(late.id))
      expect(late.reload.meta['sdp_answer']).to eq('SDP-EARLY')
      expect(late.status).to eq('completed')
    end

    # A consumer that stalled hands both over together, long after the connector saw them.
    it 'times the call by when the connector saw the pickup and the end' do
      call_id = "CALLOUT4#{command_suffix}"
      picked_up = 10.minutes.ago
      dispatch(model::Events::CallAnswered.new(call_id: call_id, sdp: 'SDP-EARLY'), ts: (picked_up.to_f * 1000).to_i)
      dispatch(model::Events::CallTerminate.new(call_id: call_id, from: caller_party, reason: nil), ts: ((picked_up + 95).to_f * 1000).to_i)
      late = Call.create!(account: account, inbox: inbox, conversation: conversation, contact: conversation.contact, provider: :whatsapp,
                          direction: :outgoing, status: 'ringing', provider_call_id: call_id, meta: {})

      described_class.new(inbox: inbox).reconcile(late)

      expect(late.reload.duration_seconds).to eq(95)
    end

    # Applied later, from a queue, and timed by when the pickup and the end arrived.
    it 'times the call from when the pickup arrived, not from when it is applied' do
      call_id = "CALLOUT6#{command_suffix}"
      freeze_time do
        dispatch(model::Events::CallAnswered.new(call_id: call_id, sdp: 'SDP-EARLY'))
        travel 40.seconds
        dispatch(model::Events::CallTerminate.new(call_id: call_id, from: caller_party, reason: nil))
        travel 5.minutes
        late = Call.create!(account: account, inbox: inbox, conversation: conversation, contact: conversation.contact, provider: :whatsapp,
                            direction: :outgoing, status: 'ringing', provider_call_id: call_id, meta: {})

        described_class.new(inbox: inbox).reconcile(late)

        expect(late.reload.status).to eq('completed')
        expect(late.duration_seconds).to eq(40)
      end
    end
  end

  describe 'an answer the connector could not use' do
    let(:lid_contact) { create(:contact, account: account, identifier: '182736451928374@lid') }
    let(:conversation) { create(:conversation, inbox: inbox, account: account, contact: lid_contact) }
    let!(:call) do
      Call.create!(account: account, inbox: inbox, conversation: conversation, contact: conversation.contact, provider: :whatsapp,
                   direction: :incoming, status: 'in_progress', provider_call_id: 'CALLX3', started_at: Time.current, meta: {})
    end

    def failed(command_id, type: 'call.accept')
      dispatch(model::Events::CommandFailed.new(command_id: command_id, command_type: type, message_id: nil,
                                                error: model::WireError.new(code: 'invalid_payload', message: 'bad sdp')))
    end

    # A shard stalled on a busy chat can read the failure minutes after the answer went out.
    it 'remembers the call an answer was for past the longest a shard can stall' do
      Whatsapp::Session::CallCommands.remember("cmd-accept-2-#{command_suffix}", 'CALLX3')

      stall = Whatsapp::Connector::Consumer::ShardWorker::BUSY_WAITS.sum
      expect(Redis::Alfred.ttl(Whatsapp::Session::CallCommands.key("cmd-accept-2-#{command_suffix}"))).to be > stall
    end

    it 'closes the call it was for as failed and refuses it on the caller\'s phone' do
      Whatsapp::Session::CallCommands.remember("cmd-accept-1-#{command_suffix}", 'CALLX3')

      expect(failed("cmd-accept-1-#{command_suffix}")).to eq(:handled)

      expect(call.reload.status).to eq('failed')
      expect(events_named('voice_call.ended').map { |p| p[:data][:call_id] }).to eq(['CALLX3'])
      expect(backend.commands.map(&:to_h)).to eq([{ 'call_id' => 'CALLX3', 'from' => { 'kind' => 'lid', 'id' => '182736451928374' } }])
    end

    # The stream delivers again a failure whose handling the database failed.
    it 'closes the call on the failure delivered again after closing it failed' do
      Whatsapp::Session::CallCommands.remember("cmd-accept-3-#{command_suffix}", 'CALLX3')
      service = instance_double(described_class)
      allow(described_class).to receive(:new).and_call_original
      allow(described_class).to receive(:new).with(inbox: inbox).and_return(service)
      allow(service).to receive(:accept_failed).and_raise(ActiveRecord::StatementInvalid, 'connection lost')

      expect { failed("cmd-accept-3-#{command_suffix}") }.to raise_error(ActiveRecord::StatementInvalid)

      allow(described_class).to receive(:new).and_call_original
      expect(failed("cmd-accept-3-#{command_suffix}")).to eq(:handled)
      expect(call.reload.status).to eq('failed')
    end

    it 'leaves the call alone for a failure it cannot place' do
      expect(failed("cmd-unknown-#{command_suffix}")).to eq(:ignored)

      expect(call.reload.status).to eq('in_progress')
      expect(backend.commands).to be_empty
    end
  end

  describe 'the end of a call' do
    let(:conversation) { create(:conversation, inbox: inbox, account: account) }

    def call_in(status, direction, id)
      Call.create!(account: account, inbox: inbox, conversation: conversation, contact: conversation.contact, provider: :whatsapp,
                   direction: direction, status: status, provider_call_id: id, started_at: 1.minute.ago)
    end

    def terminate(id, reason: nil)
      dispatch(model::Events::CallTerminate.new(call_id: id, from: caller_party, reason: reason))
    end

    it 'closes a call the way the Cloud path does' do
      ringing = call_in('ringing', :incoming, 'CALLX5')
      answered = call_in('in_progress', :outgoing, 'CALLOUT3')

      expect(terminate('CALLX5')).to eq(:handled)
      expect(terminate('CALLOUT3')).to eq(:handled)

      expect(ringing.reload.status).to eq('no_answer')
      expect(answered.reload.status).to eq('completed')
      # Timed from the pickup, since the connector reports no duration.
      expect(answered.duration_seconds).to be_within(2).of(60)
      expect(ringing.duration_seconds).to be_nil
      expect(events_named('voice_call.ended').map { |p| p[:data][:call_id] }).to eq(%w[CALLX5 CALLOUT3])
    end

    it 'records a failure the connector names as one' do
      call = call_in('ringing', :outgoing, 'CALLOUT4')

      terminate('CALLOUT4', reason: 'rejected')

      expect(call.reload.status).to eq('failed')
    end

    it 'leaves a closed call as it is when the end arrives again' do
      call = call_in('ringing', :incoming, 'CALLX5')
      terminate('CALLX5')
      before = call.reload.attributes

      expect(terminate('CALLX5')).to eq(:handled)

      expect(call.reload.attributes).to eq(before)
      expect(events_named('voice_call.ended').size).to eq(1)
    end

    it 'has nothing to close for a call shown only as a line' do
      offer('ATIVIDADE1', sdp: nil)

      expect { terminate('ATIVIDADE1') }.not_to change(Call, :count)
      expect(call_lines.count).to eq(1)
    end
  end
end
