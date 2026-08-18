require 'rails_helper'

RSpec.describe Whatsapp::Session::Inbound::Handlers::GroupJoined do
  subject(:dispatch) do
    with_modified_env WHATSAPP_GROUPS_ENABLED: 'true' do
      Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event)
    end
  end

  let(:channel) do
    create(:channel_whatsapp, provider: 'native', phone_number: '+5541988887777',
                              validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:model) { Whatsapp::Session::Model }
  let(:group) { model::Address.group('120363041234567890') }
  let(:info) do
    model::GroupInfo.new(
      group: group, subject: 'Equipe de Vendas', description: 'Combinados do time',
      participants: [
        model::GroupInfo::Participant.new(party: model::Party.new(phone: '5541999990000', push_name: 'Ana'), role: 'admin'),
        model::GroupInfo::Participant.new(party: model::Party.new(phone: '5541977776666', push_name: 'Bruno'))
      ]
    )
  end
  let(:event) { model::Event.build(model::Events::GroupJoined.new(info: info)) }

  it 'is ignored while the group capability is off' do
    expect(Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event)).to eq(:ignored)
  end

  it 'opens the group with its members and its metadata' do
    expect(dispatch).to eq(:handled)

    group_contact = inbox.contacts.find_by(identifier: '120363041234567890@g.us')
    expect(group_contact.name).to eq('Equipe de Vendas')
    expect(group_contact.additional_attributes['description']).to eq('Combinados do time')
    expect(group_contact.group_memberships.active.count).to eq(2)
    expect(group_contact.conversations).to be_present
  end

  # An ordinary contact update does not carry `group_members`, so without this an open
  # dashboard keeps showing the roster (and the admin rights) the group had before.
  it 'broadcasts the roster it just synced' do
    channel
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original
    expect(Rails.configuration.dispatcher).to receive(:dispatch).with(
      Events::Types::CONTACT_GROUP_SYNCED, anything, hash_including(:contact)
    ).at_least(:once)

    dispatch
  end
end
