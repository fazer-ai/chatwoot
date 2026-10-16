require 'rails_helper'

describe Whatsapp::NumberRecheckService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'baileys', validate_provider_config: false, sync_templates: false,
                              provider_connection: { 'connection' => 'open' })
  end
  let(:contact) { create(:contact, account: account, phone_number: '+5585988246590') }
  let(:checked_at) { 2.days.ago.change(usec: 0) }
  let(:contact_inbox) do
    create(:contact_inbox, contact: contact, inbox: channel.inbox, source_id: '5585988246590', whatsapp_missing_checked_at: checked_at)
  end
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox, contact: contact, contact_inbox: contact_inbox) }

  def answer(response)
    allow_any_instance_of(Channel::Whatsapp).to receive(:on_whatsapp).and_return(response) # rubocop:disable RSpec/AnyInstance
  end

  def perform = described_class.new(conversation: conversation).perform

  it 'clears the flag when the number has registered since' do
    answer({ 'jid' => '5585988246590@s.whatsapp.net', 'exists' => true })

    perform

    expect(contact_inbox.reload.whatsapp_missing_checked_at).to be_nil
  end

  # The address this thread sends to has to follow the number WhatsApp knows, the same way a
  # new conversation's does, or clearing the warning would point the agent at a dead address.
  it 'moves the contact and the thread to the canonical number WhatsApp answers with' do
    answer({ 'jid' => '558588246590@s.whatsapp.net', 'exists' => true })

    perform

    expect(contact.reload.phone_number).to eq('+558588246590')
    expect(contact_inbox.reload.source_id).to eq('558588246590')
  end

  it 'keeps the address when another contact inbox of the inbox already holds the canonical one' do
    create(:contact_inbox, inbox: channel.inbox, source_id: '558588246590')
    answer({ 'jid' => '558588246590@s.whatsapp.net', 'exists' => true })

    perform

    expect(contact_inbox.reload.source_id).to eq('5585988246590')
    expect(contact_inbox.whatsapp_missing_checked_at).to be_nil
  end

  it 'moves the check date forward when the number still has no WhatsApp' do
    answer({ 'jid' => '5585988246590@s.whatsapp.net', 'exists' => false })

    freeze_time do
      perform

      expect(contact_inbox.reload.whatsapp_missing_checked_at).to eq(Time.current)
    end
  end

  it 'keeps the flag and its date when the lookup fails' do
    allow_any_instance_of(Channel::Whatsapp).to receive(:on_whatsapp).and_raise(StandardError, 'boom') # rubocop:disable RSpec/AnyInstance

    perform

    expect(contact_inbox.reload.whatsapp_missing_checked_at).to eq(checked_at)
  end

  it 'does not ask inside the recheck window' do
    contact_inbox.update!(whatsapp_missing_checked_at: 10.minutes.ago)
    expect_any_instance_of(Channel::Whatsapp).not_to receive(:on_whatsapp) # rubocop:disable RSpec/AnyInstance

    perform
  end

  # Two agents opening the same stale conversation enqueue two jobs; one lookup is enough.
  it 'leaves the lookup to the worker that already holds the claim' do
    Redis::LockManager.new.lock("whatsapp_number_recheck:#{contact_inbox.id}", 60)
    expect_any_instance_of(Channel::Whatsapp).not_to receive(:on_whatsapp) # rubocop:disable RSpec/AnyInstance

    perform

    expect(contact_inbox.reload.whatsapp_missing_checked_at).to eq(checked_at)
  end

  it 'does not ask again when the worker before it already answered' do
    answer({ 'jid' => '5585988246590@s.whatsapp.net', 'exists' => true })
    service = described_class.new(conversation: conversation)
    service.send(:contact_inbox) # memoized with the stale date, as a queued job would hold it
    ContactInbox.find(contact_inbox.id).update!(whatsapp_missing_checked_at: 1.minute.ago) # the other worker

    service.perform

    expect(contact_inbox.reload.whatsapp_missing_checked_at).to be_present
  end

  it 'tells the dashboard what changed' do
    answer({ 'jid' => '5585988246590@s.whatsapp.net', 'exists' => true })
    allow(Rails.configuration.dispatcher).to receive(:dispatch)

    perform

    expect(Rails.configuration.dispatcher).to have_received(:dispatch)
      .with(Events::Types::CONVERSATION_UPDATED, anything, hash_including(conversation: conversation))
  end
end
