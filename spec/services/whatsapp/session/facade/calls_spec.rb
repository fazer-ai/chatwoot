require 'rails_helper'

RSpec.describe Whatsapp::Session::Facade::Calls do
  subject(:facade) { channel.provider_service }

  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:backend) { Whatsapp::Session::Backends::Fake.new(channel) }
  let(:model) { Whatsapp::Session::Model }
  # The call command registry lives in Redis, which outlives an example.
  let(:command_suffix) { SecureRandom.hex(4) }

  before do
    allow(Whatsapp::Session::Registry).to receive(:backend_for).and_return(backend)
    allow(Whatsapp::Connector::Client).to receive(:carries_calls?).and_return(true)
    channel.account.enable_features!('channel_voice')
  end

  def turn_calling(enabled, inbound: true)
    channel.update!(provider_config: channel.provider_config.merge('calling_enabled' => enabled, 'inbound_calls_enabled' => inbound))
  end

  describe 'the call policy on the connect' do
    # `auto_reject` is never sent: the connector reads it as no calls on the session at all,
    # the placed ones included, and a refusal from a linked device ends the call on the
    # phone too (#850). Without calling the field is left out, and the phone rings.
    it 'asks for the voice whenever calling is on, and states no policy when it is off' do
      policies = [[false, true], [true, true], [true, false]].map do |calling, inbound|
        turn_calling(calling, inbound: inbound)
        facade.setup_channel_provider
        backend.last_command.calls
      end

      expect(policies).to eq([nil, { 'answer' => true }, { 'answer' => true }])
    end

    it 'states no policy on an installation without voice, so the phone rings' do
      turn_calling(true)
      channel.account.disable_features!('channel_voice')
      facade.setup_channel_provider

      expect(backend.last_command.calls).to be_nil
    end
  end

  describe 'answering, refusing and hanging up' do
    it 'turns the Calling API steps into the connector commands' do
      expect(facade.pre_accept_call('CALLX3', 'SDP-ANSWER-BROWSER')).to be(true)
      expect(backend.commands).to be_empty

      expect(facade.accept_call('CALLX3', 'SDP-ANSWER-BROWSER')).to be(true)
      facade.reject_call('CALLX4', from: model::Address.lid('182736451928374'))
      facade.terminate_call('CALLX6')

      expect(backend.commands.map(&:to_h)).to eq(
        [
          { 'call_id' => 'CALLX3', 'sdp' => 'SDP-ANSWER-BROWSER' },
          { 'call_id' => 'CALLX4', 'from' => { 'kind' => 'lid', 'id' => '182736451928374' } },
          { 'call_id' => 'CALLX6' }
        ]
      )
      expect(backend.commands.map(&:wire_type)).to eq(%w[call.accept call.reject call.terminate])
    end

    # The answer is fire and forget, so its failure names the command; this is what ties it back.
    it 'remembers which call an answer was for' do
      allow(backend).to receive(:accept_call).and_return("cmd-accept-1-#{command_suffix}")

      expect(facade.accept_call('CALLX3', 'SDP')).to be(true)

      expect(Whatsapp::Session::CallCommands.failed("cmd-accept-1-#{command_suffix}").call_id).to eq('CALLX3')
      # Delivered again before it was applied, it is the same failure of the same call.
      expect(Whatsapp::Session::CallCommands.failed("cmd-accept-1-#{command_suffix}").call_id).to eq('CALLX3')
      Whatsapp::Session::CallCommands.settled("cmd-accept-1-#{command_suffix}")
      expect(Whatsapp::Session::CallCommands.failed("cmd-accept-1-#{command_suffix}")).to be_nil
    end

    # A refusal or a hang-up the connector could not carry out is sent again, and for that
    # the refusal's caller and the attempt travel with the command.
    it 'remembers what a refusal and a hang-up need to be sent again' do
      allow(backend).to receive(:reject_call).and_return("cmd-reject-1-#{command_suffix}")
      allow(backend).to receive(:terminate_call).and_return("cmd-terminate-1-#{command_suffix}")

      expect(facade.reject_call('CALLX4', from: model::Address.lid('182736451928374'), attempt: 2)).to be(true)
      expect(facade.terminate_call('CALLX6')).to be(true)

      expect(Whatsapp::Session::CallCommands.failed("cmd-reject-1-#{command_suffix}").to_h).to eq(
        call_id: 'CALLX4', from: { 'kind' => 'lid', 'id' => '182736451928374' }, attempt: 2
      )
      expect(Whatsapp::Session::CallCommands.failed("cmd-terminate-1-#{command_suffix}").to_h).to eq(call_id: 'CALLX6', from: nil, attempt: 0)
    end

    it 'answers that a hang-up failed when its failure was read first' do
      allow(backend).to receive(:terminate_call).and_return("cmd-terminate-2-#{command_suffix}")
      expect(Whatsapp::Session::CallCommands.failed("cmd-terminate-2-#{command_suffix}")).to be_nil

      expect(facade.terminate_call('CALLX6')).to be(false)
    end

    # The connector refuses some answers at once, and its failure can be read before the
    # request that published the answer writes down which call it was for.
    it 'answers that the answer failed when its failure was read first' do
      allow(backend).to receive(:accept_call).and_return("cmd-accept-2-#{command_suffix}")
      expect(Whatsapp::Session::CallCommands.failed("cmd-accept-2-#{command_suffix}")).to be_nil

      expect(facade.accept_call('CALLX3', 'SDP')).to be(false)
    end

    # Uazapi pairs a phone too and carries no call: the flow must hear a refusal rather than
    # a call that seemed to go through.
    it 'refuses on a provider that does not carry calls' do
      allow(channel).to receive(:session_capabilities).and_return(%w[calls])

      expect { facade.accept_call('CALLX3', 'x') }.to raise_error(Whatsapp::Session::Errors::NotSupported)
      expect { facade.initiate_call('5541999990000', 'x') }.to raise_error(Whatsapp::Session::Errors::NotSupported)
      expect(backend.commands).to be_empty
    end
  end

  # Without the connector's call port the call.start would only come back unsupported;
  # refused here, the agent reads why instead of a generic failure.
  it 'refuses a call with the reason when the connector carries no call voice' do
    allow(Whatsapp::Connector::Client).to receive(:carries_calls?).and_return(false)

    expect { facade.initiate_call('5541999990000', 'SDP-OFFER') }
      .to raise_error(Whatsapp::Session::Errors::NotSupported, I18n.t('errors.whatsapp.calls.connector_without_calls'))
    expect(backend.commands).to be_empty
  end

  describe 'placing a call' do
    let(:contact) { create(:contact, account: channel.account, phone_number: '+5541999990000', identifier: '182736451928374@lid') }

    # The connector knows which number a LID is paired with; the contact's own number can
    # belong to somebody else after an edit or a merge.
    it 'dials the number the connector pairs with the LID the conversation is on' do
      contact.update!(phone_number: '+5521988880000')
      create(:contact_inbox, contact: contact, inbox: channel.inbox, source_id: '182736451928374')

      expect(facade.initiate_call('182736451928374', 'SDP-OFFER')).to eq('call_id' => 'FAKECALL0001')
      expect(backend.commands_of('contact.resolve').first.to_h).to eq('party' => { 'kind' => 'lid', 'id' => '182736451928374' })
      expect(backend.last_command.to_h).to eq('to' => { 'kind' => 'phone', 'id' => '5541999990000' }, 'sdp' => 'SDP-OFFER')
    end

    it 'dials a conversation on a number the connector knows at that number, whatever the contact says now' do
      contact.update!(phone_number: '+5521988880000')
      create(:contact_inbox, contact: contact, inbox: channel.inbox, source_id: '5541999990000')

      facade.initiate_call('5541999990000', 'SDP-OFFER')

      expect(backend.last_command.to.id).to eq('5541999990000')
    end

    it 'dials a conversation on the contact\'s own number' do
      create(:contact_inbox, contact: contact, inbox: channel.inbox, source_id: '5541999990000')
      contact.update!(phone_number: '+5511977776666')
      create(:contact_inbox, contact: contact, inbox: channel.inbox, source_id: '5511977776666')

      facade.initiate_call('5511977776666', 'SDP-OFFER', contact: contact)

      expect(backend.last_command.to.id).to eq('5511977776666')
    end

    # The contact panel hands over the contact's number before any thread with it exists.
    it 'dials a contact\'s number from the contact panel, with no thread yet' do
      contact.update!(phone_number: '+5511977776666')

      facade.initiate_call('5511977776666', 'SDP-OFFER', contact: contact)

      expect(backend.last_command.to.id).to eq('5511977776666')
    end

    # A thread on the contact's own number is on a number, whatever else the digits are.
    it 'dials a thread on the contact\'s own number as that number, even when the digits are a known LID' do
      contact.update!(phone_number: '+182736451928374')

      facade.initiate_call('182736451928374', 'SDP-OFFER', contact: contact)

      expect(backend.last_command.to.id).to eq('182736451928374')
    end

    # Digits the connector knows as a LID of one phone and as another number are not guessed.
    it 'refuses digits the connector knows both as a LID and as another number' do
      contact.update!(phone_number: '+5521988880000')
      allow(backend).to receive(:resolve_contact).and_wrap_original do |original, command|
        next Whatsapp::Session::Model::Party.new(phone: '5511900000000', lid: '182736451928374', push_name: nil) if command.party.kind == 'phone'

        original.call(command)
      end

      expect { facade.initiate_call('182736451928374', 'SDP-OFFER', contact: contact) }.to raise_error(Whatsapp::Session::Errors::InvalidPayload)
      expect(backend.commands_of('call.start')).to be_empty
    end

    # The dial runs inside a request that is killed after 15 s. Every connector call it makes
    # is bounded by what is left of one budget below that, so the connector, which drops a
    # command past its deadline, never rings somebody after the request died.
    # The callee may be another native inbox here, which records nothing of this call until
    # it reads the offer. The number being rung is marked first, so that side can tell this
    # dial from a call off a handset.
    it 'marks the number it rings before it places the call' do
      marked = nil
      allow(backend).to receive(:start_call).and_wrap_original do |original, *args, **kwargs|
        marked = Redis::Alfred.get(format(Redis::Alfred::WHATSAPP_CONNECTOR_CALL_DIALING, phone: '5511999990000', channel_id: channel.id))
        original.call(*args, **kwargs)
      end

      facade.initiate_call('5511999990000', 'SDP-OFFER', contact: contact, number: true)

      expect(marked).to be_present
    end

    describe 'the time a dial may take' do
      let(:budget) { described_class::CALL_INITIATION_BUDGET }

      it 'bounds every connector call of the dial by what is left of one budget' do
        timeouts = []
        %i[resolve_contact start_call].each do |name|
          allow(backend).to receive(name).and_wrap_original do |original, *args, **kwargs|
            timeouts << [name, kwargs[:timeout]]
            original.call(*args, **kwargs)
          end
        end

        facade.initiate_call('182736451928374', 'SDP-OFFER', contact: contact)

        expect(timeouts.map(&:first)).to include(:resolve_contact, :start_call)
        expect(timeouts.map(&:last)).to all(be_a(Numeric).and(be <= budget))
        expect(budget).to be < 15
      end

      it 'does not place the call when the lookups left too little of the budget' do
        clock = [0.0]
        allow(Process).to receive(:clock_gettime).and_call_original
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { clock.first }
        allow(backend).to receive(:resolve_contact).and_wrap_original do |original, *args, **kwargs|
          clock[0] += budget
          original.call(*args, **kwargs)
        end

        expect { facade.initiate_call('182736451928374', 'SDP-OFFER', contact: contact) }
          .to raise_error(Whatsapp::Session::Errors::Timeout)
        expect(backend.commands_of('call.start')).to be_empty
      end
    end

    # A number picked as one is dialled as one, even when the same digits are a LID the
    # connector pairs with somebody else's phone.
    it 'dials a number picked from the contact panel as that number' do
      facade.initiate_call('182736451928374', 'SDP-OFFER', contact: contact, number: true)

      expect(backend.last_command.to_h).to eq('to' => { 'kind' => 'phone', 'id' => '182736451928374' }, 'sdp' => 'SDP-OFFER')
      expect(backend.commands_of('contact.resolve')).to be_empty
    end

    # The digits of a LID the connector pairs with nothing can be somebody's phone number.
    it 'refuses digits nothing says are a number' do
      create(:contact_inbox, contact: contact, inbox: channel.inbox, source_id: '998877665544332')

      expect { facade.initiate_call('998877665544332', 'SDP-OFFER') }.to raise_error(Whatsapp::Session::Errors::InvalidPayload)
      expect(backend.commands_of('call.start')).to be_empty
    end

    # Another contact of the account with the same digits says nothing about this thread.
    it 'refuses digits only an unrelated contact carries as a number' do
      create(:contact, account: channel.account, phone_number: '+998877665544332')
      create(:contact_inbox, contact: contact, inbox: channel.inbox, source_id: '998877665544332')

      expect { facade.initiate_call('998877665544332', 'SDP-OFFER', contact: contact) }.to raise_error(Whatsapp::Session::Errors::InvalidPayload)
      expect(backend.commands_of('call.start')).to be_empty
    end

    # The store holds the pairs this account has met, and a thread on a LID can predate them.
    # WhatsApp itself answers the contact's number with the LID it is behind, and the number
    # is dialled only when that is the LID the thread is on.
    describe 'a LID the connector has not paired yet' do
      let(:unpaired) { '998877665544332' }

      before do
        contact.update!(phone_number: '+5521988880000')
        create(:contact_inbox, contact: contact, inbox: channel.inbox, source_id: unpaired)
      end

      def check_answers(exists: true, phone: '5521988880000', address: model::Address.lid('998877665544332'))
        allow(backend).to receive(:check_numbers).and_wrap_original do |original, command, **kwargs|
          original.call(command, **kwargs)
          [model::NumberCheck.new(phone: phone, exists: exists, address: address)]
        end
      end

      it 'dials the contact\'s number when WhatsApp puts it behind the LID the thread is on' do
        check_answers

        facade.initiate_call(unpaired, 'SDP-OFFER', contact: contact)

        expect(backend.commands_of('contact.check').map(&:to_h)).to eq([{ 'phones' => ['5521988880000'] }])
        expect(backend.last_command.to_h).to eq('to' => { 'kind' => 'phone', 'id' => '5521988880000' }, 'sdp' => 'SDP-OFFER')
      end

      it 'dials the number WhatsApp answered with, not the one the contact carries' do
        check_answers(phone: '552188880000')

        facade.initiate_call(unpaired, 'SDP-OFFER', contact: contact)

        expect(backend.last_command.to.id).to eq('552188880000')
      end

      {
        'puts the number behind another LID' => { address: Whatsapp::Session::Model::Address.lid('111122223333444') },
        'says the number is not on WhatsApp' => { exists: false },
        'names no LID for the number' => { address: Whatsapp::Session::Model::Address.phone('5521988880000') }
      }.each do |what, answer|
        it "refuses without dialling when WhatsApp #{what}" do
          check_answers(**answer)

          expect { facade.initiate_call(unpaired, 'SDP-OFFER', contact: contact) }.to raise_error(Whatsapp::Session::Errors::InvalidPayload)
          expect(backend.commands_of('call.start')).to be_empty
        end
      end

      it 'refuses without asking when the contact has no number' do
        contact.update!(phone_number: nil)

        expect { facade.initiate_call(unpaired, 'SDP-OFFER', contact: contact) }.to raise_error(Whatsapp::Session::Errors::InvalidPayload)
        expect(backend.commands_of('contact.check')).to be_empty
        expect(backend.commands_of('call.start')).to be_empty
      end

      it 'refuses without dialling when the check fails' do
        allow(backend).to receive(:check_numbers).and_raise(Whatsapp::Session::Errors::Timeout, 'contact.check timed out')

        expect { facade.initiate_call(unpaired, 'SDP-OFFER', contact: contact) }.to raise_error(Whatsapp::Session::Errors::Timeout)
        expect(backend.commands_of('call.start')).to be_empty
      end

      it 'does not ask when the connector already pairs the LID' do
        facade.initiate_call('182736451928374', 'SDP-OFFER', contact: contact)

        expect(backend.commands_of('contact.check')).to be_empty
        expect(backend.last_command.to.id).to eq('5541999990000')
      end

      it 'gives the check only what the budget can spare past the call.start window' do
        given = nil
        allow(backend).to receive(:check_numbers).and_wrap_original do |original, command, **kwargs|
          given = kwargs[:timeout]
          original.call(command, **kwargs)
          [model::NumberCheck.new(phone: '5521988880000', exists: true, address: model::Address.lid(unpaired))]
        end

        facade.initiate_call(unpaired, 'SDP-OFFER', contact: contact)

        expect(given).to be_a(Integer).and(be > Whatsapp::Connector::Client::DEADLINE_MARGIN)
        expect(given).to be <= described_class::CALL_INITIATION_BUDGET - described_class::CALL_START_MIN_WINDOW
      end

      it 'still has the call.start window after a check that took all it was given' do
        clock = [0.0]
        allow(Process).to receive(:clock_gettime).and_call_original
        allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC) { clock.first }
        allow(backend).to receive(:check_numbers).and_wrap_original do |original, command, **kwargs|
          clock[0] += kwargs.fetch(:timeout)
          original.call(command, **kwargs)
          [model::NumberCheck.new(phone: '5521988880000', exists: true, address: model::Address.lid(unpaired))]
        end

        facade.initiate_call(unpaired, 'SDP-OFFER', contact: contact)

        expect(backend.last_command.to.id).to eq('5521988880000')
        expect(clock.first).to be <= described_class::CALL_INITIATION_BUDGET - described_class::CALL_START_MIN_WINDOW
      end
    end

    # The same offer is the same request retried; a new click is a new offer.
    it 'keys the call on its offer' do
      facade.initiate_call('5541999990000', 'SDP-OFFER-1')
      facade.initiate_call('5541999990000', 'SDP-OFFER-1')
      facade.initiate_call('5541999990000', 'SDP-OFFER-2')

      keys = backend.idempotency_keys
      expect(keys).to all(be_present)
      expect(keys.uniq.size).to eq(2)
      expect(keys.first).to eq(keys.second)
    end
  end
end
