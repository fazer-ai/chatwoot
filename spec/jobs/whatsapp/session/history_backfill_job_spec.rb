require 'rails_helper'

RSpec.describe Whatsapp::Session::HistoryBackfillJob do
  let(:channel) do
    create(:channel_whatsapp, provider: 'uazapi', validate_provider_config: false, sync_templates: false,
                              provider_config: { 'base_url' => 'https://uazapi.test', 'token' => 'x', 'history_sync' => true })
  end
  let(:inbox) { channel.inbox }
  let(:facade) { instance_double(Whatsapp::Session::Facade, request_history: true) }

  before { allow(channel).to receive(:provider_service).and_return(facade) }

  def conversation_with_contact(last_activity_at:)
    contact = create(:contact, account: inbox.account)
    contact_inbox = create(:contact_inbox, contact: contact, inbox: inbox)
    create(:conversation, inbox: inbox, account: inbox.account, contact: contact, contact_inbox: contact_inbox,
                          last_activity_at: last_activity_at)
  end

  it 'asks the phone about the conversations the inbox already holds' do
    conversation = conversation_with_contact(last_activity_at: 1.hour.ago)

    described_class.perform_now(channel)

    expect(facade).to have_received(:request_history).with(conversation.contact)
  end

  # What arrives is indistinguishable from the dump that follows a pairing, so the window
  # is the only thing that will tell the import these frames were asked for. Opened before
  # the first request, since it also puts `history` on the webhook subscription.
  it 'opens the window before it asks' do
    conversation_with_contact(last_activity_at: 1.hour.ago)

    described_class.perform_now(channel)

    expect(Whatsapp::Session::HistoryBackfill.pending?(channel)).to be(true)
  end

  # Recovering one outage must not require turning on the dump that then repeats at every
  # future pairing: the setting is standing consent, this is a single act.
  it 'does not need the connect-time setting' do
    channel.update!(provider_config: channel.provider_config.merge('history_sync' => false))
    conversation = conversation_with_contact(last_activity_at: 1.hour.ago)

    described_class.perform_now(channel)

    expect(facade).to have_received(:request_history).with(conversation.contact)
  end

  it 'stops at the cap, most recently active first' do
    stub_const("#{described_class}::CHATS", 2)
    recent = Array.new(3) { |i| conversation_with_contact(last_activity_at: (i + 1).hours.ago) }

    described_class.perform_now(channel)

    expect(facade).to have_received(:request_history).with(recent.first.contact)
    expect(facade).not_to have_received(:request_history).with(recent.last.contact)
  end

  # A number that has left WhatsApp says nothing about the next chat, and the operator
  # pressed a button that means "as much as you can get".
  it 'keeps going when one chat is refused' do
    first = conversation_with_contact(last_activity_at: 1.hour.ago)
    second = conversation_with_contact(last_activity_at: 2.hours.ago)
    allow(facade).to receive(:request_history).with(first.contact).and_raise(Whatsapp::Session::Errors::ProviderUnavailable)

    described_class.perform_now(channel)

    expect(facade).to have_received(:request_history).with(second.contact)
  end
end
