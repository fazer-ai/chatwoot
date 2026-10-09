require 'rails_helper'

RSpec.describe Whatsapp::Session::Facade::Calls do
  subject(:facade) { channel.provider_service }

  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:backend) { Whatsapp::Session::Backends::Fake.new(channel) }
  let(:model) { Whatsapp::Session::Model }

  before do
    allow(Whatsapp::Session::Registry).to receive(:backend_for).and_return(backend)
    channel.account.enable_features!('channel_voice')
  end

  def turn_calling(enabled, inbound: true)
    channel.update!(provider_config: channel.provider_config.merge('calling_enabled' => enabled, 'inbound_calls_enabled' => inbound))
  end

  describe 'the call policy on the connect' do
    # `auto_reject` beside `answer` is read by the connector as no calls on the session at
    # all, the placed ones included. So incoming calls turned off never put it there.
    it 'asks for the voice whenever calling is on, and refuses every call only when it is off' do
      policies = [[false, true], [true, true], [true, false]].map do |calling, inbound|
        turn_calling(calling, inbound: inbound)
        facade.setup_channel_provider
        backend.last_command.calls
      end

      expect(policies).to eq([{ 'auto_reject' => true }, { 'answer' => true }, { 'answer' => true }])
    end

    it 'keeps refusing calls on an installation without voice' do
      turn_calling(true)
      channel.account.disable_features!('channel_voice')
      facade.setup_channel_provider

      expect(backend.last_command.calls).to eq({ 'auto_reject' => true })
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

    # Uazapi pairs a phone too and carries no call: the flow must hear a refusal rather than
    # a call that seemed to go through.
    it 'refuses on a provider that does not carry calls' do
      allow(channel).to receive(:session_capabilities).and_return(%w[calls])

      expect { facade.accept_call('CALLX3', 'x') }.to raise_error(Whatsapp::Session::Errors::NotSupported)
      expect { facade.initiate_call('5541999990000', 'x') }.to raise_error(Whatsapp::Session::Errors::NotSupported)
      expect(backend.commands).to be_empty
    end
  end

  describe 'placing a call' do
    let(:contact) { create(:contact, account: channel.account, phone_number: '+5541999990000', identifier: '182736451928374@lid') }

    it 'dials the number behind a conversation addressed by LID and answers in the Cloud shape' do
      create(:contact_inbox, contact: contact, inbox: channel.inbox, source_id: '182736451928374')

      expect(facade.initiate_call('182736451928374', 'SDP-OFFER')).to eq('call_id' => 'FAKECALL0001')
      expect(backend.last_command.to_h).to eq('to' => { 'kind' => 'phone', 'id' => '5541999990000' }, 'sdp' => 'SDP-OFFER')
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

    it 'refuses a contact with no number to dial' do
      contact.update!(phone_number: nil)
      create(:contact_inbox, contact: contact, inbox: channel.inbox, source_id: '182736451928374')

      expect { facade.initiate_call('182736451928374', 'SDP-OFFER') }.to raise_error(Whatsapp::Session::Errors::InvalidPayload)
      expect(backend.commands).to be_empty
    end
  end
end
