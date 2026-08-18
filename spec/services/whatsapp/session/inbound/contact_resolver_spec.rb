require 'rails_helper'

RSpec.describe Whatsapp::Session::Inbound::ContactResolver do
  let(:channel) { create(:channel_whatsapp, provider: 'native', validate_provider_config: false, sync_templates: false) }
  let(:inbox) { channel.inbox }
  let(:model) { Whatsapp::Session::Model }
  let(:party) { model::Party.new(phone: '5541999990000', lid: '182736451928374', push_name: 'Ana Souza') }

  it 'keys the contact_inbox by LID and fills the contact in' do
    contact_inbox = described_class.new(inbox: inbox, party: party, overwrite: true).perform

    expect(contact_inbox.source_id).to eq('182736451928374')
    expect(contact_inbox.contact).to have_attributes(
      name: 'Ana Souza', phone_number: '+5541999990000', identifier: '182736451928374@lid'
    )
  end

  # Consolidation needs a phone *and* a LID, so it can do nothing for a phone-only
  # party. Without a variant-aware lookup the builder matches exactly, misses the row
  # the contact is already filed under, and files the same person a second time with a
  # conversation of their own.
  context 'when the contact is already filed under the other ninth-digit form' do
    let(:party) { model::Party.new(phone: '5541988887777', push_name: 'Bruno') }
    let!(:existing) do
      contact = create(:contact, account: channel.account, phone_number: '+554188887777')
      create(:contact_inbox, inbox: inbox, contact: contact, source_id: '554188887777')
    end

    it 'reuses it instead of creating a second contact' do
      expect { described_class.new(inbox: inbox, party: party, overwrite: true).perform }
        .not_to change(inbox.contact_inboxes, :count)

      expect(described_class.new(inbox: inbox, party: party, overwrite: true).perform.id).to eq(existing.id)
    end
  end

  # An unordered `IN` over both forms can hand back either row. Picking the alternate
  # one files the message under the wrong contact, and `overwrite` then tries to move
  # the exact number onto a contact that does not own it, which the uniqueness check
  # refuses: the message is lost rather than merely misfiled.
  context 'when both ninth-digit forms are already filed' do
    let(:party) { model::Party.new(phone: '5541988887777', push_name: 'Bruno') }
    let!(:exact) do
      contact = create(:contact, account: channel.account, name: 'Bruno Exato', phone_number: '+5541988887777')
      create(:contact_inbox, inbox: inbox, contact: contact, source_id: '5541988887777')
    end

    before do
      contact = create(:contact, account: channel.account, name: 'Bruno Antigo', phone_number: '+554188887777')
      create(:contact_inbox, inbox: inbox, contact: contact, source_id: '554188887777')
    end

    it 'files the message under the number as reported' do
      expect(described_class.new(inbox: inbox, party: party, overwrite: true).perform.id).to eq(exact.id)
    end
  end

  it 'answers nil for a party with nothing to key on' do
    expect(described_class.new(inbox: inbox, party: model::Party.new(push_name: 'Ana')).perform).to be_nil
  end

  it 'replaces a name that is only the contact phone number' do
    contact = create(:contact, account: channel.account, name: '5541999990000', phone_number: '+5541999990000')
    create(:contact_inbox, contact: contact, inbox: inbox, source_id: '182736451928374')

    described_class.new(inbox: inbox, party: party, overwrite: true).perform

    expect(contact.reload.name).to eq('Ana Souza')
  end

  it 'keeps a name a human typed' do
    contact = create(:contact, account: channel.account, name: 'Ana (financeiro)', phone_number: '+5541999990000')
    create(:contact_inbox, contact: contact, inbox: inbox, source_id: '182736451928374')

    described_class.new(inbox: inbox, party: party, overwrite: true).perform

    expect(contact.reload.name).to eq('Ana (financeiro)')
  end

  it 'only fills blanks for a group participant' do
    contact = create(:contact, account: channel.account, name: 'Ana', phone_number: '+5541999999999')
    create(:contact_inbox, contact: contact, inbox: inbox, source_id: '182736451928374')

    described_class.new(inbox: inbox, party: party).perform

    expect(contact.reload.phone_number).to eq('+5541999999999')
  end

  it 'merges a contact_inbox that was keyed by phone before the LID showed up' do
    contact = create(:contact, account: channel.account, name: 'Ana', phone_number: '+5541999990000')
    create(:contact_inbox, contact: contact, inbox: inbox, source_id: '5541999990000')

    contact_inbox = described_class.new(inbox: inbox, party: party, overwrite: true).perform

    expect(contact_inbox.contact_id).to eq(contact.id)
    expect(inbox.contacts.count).to eq(1)
  end

  it 'asks for the profile picture of a contact that has none' do
    contact_inbox = described_class.new(inbox: inbox, party: party, overwrite: true).perform

    expect(Whatsapp::Session::UpdateContactAvatarJob).to have_been_enqueued.with(contact_inbox.contact, inbox, party.to_h)
  end
end
