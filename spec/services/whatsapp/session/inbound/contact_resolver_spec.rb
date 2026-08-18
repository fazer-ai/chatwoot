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
