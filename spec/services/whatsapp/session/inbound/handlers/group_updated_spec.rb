require 'rails_helper'

RSpec.describe Whatsapp::Session::Inbound::Handlers::GroupUpdated do
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
  let(:actor) { model::Party.new(phone: '5541999990000', lid: '182736451928374', push_name: 'Ana Souza') }
  let(:changes) { model::Events::GroupUpdated::Changes.new(subject: 'Equipe de Vendas') }
  let(:event) { model::Event.build(model::Events::GroupUpdated.new(group: group, actor: actor, changes: changes)) }

  it 'is ignored while the group capability is off' do
    expect(Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event)).to eq(:ignored)
  end

  it 'renames the group and records who did it' do
    expect(dispatch).to eq(:handled)

    group_contact = inbox.contacts.find_by(identifier: '120363041234567890@g.us')
    expect(group_contact.name).to eq('Equipe de Vendas')
    activity = group_contact.conversations.last.messages.last
    expect(activity.message_type).to eq('activity')
    expect(activity.content).to include('Equipe de Vendas')
  end

  context 'when a setting changed' do
    let(:changes) { model::Events::GroupUpdated::Changes.new(announce: true, locked: false) }

    it 'persists both settings and writes one activity each' do
      expect(dispatch).to eq(:handled)

      group_contact = inbox.contacts.find_by(identifier: '120363041234567890@g.us')
      expect(group_contact.additional_attributes).to include('announce' => true, 'restrict' => false)
      expect(group_contact.conversations.last.messages.where(message_type: :activity).count).to eq(2)
    end
  end

  context 'when the description was removed' do
    let(:changes) { model::Events::GroupUpdated::Changes.new(description: '') }

    it 'clears it and says so' do
      expect(dispatch).to eq(:handled)

      group_contact = inbox.contacts.find_by(identifier: '120363041234567890@g.us')
      expect(group_contact.additional_attributes['description']).to be_nil
      expect(group_contact.conversations.last.messages.last.content).to include('removed the group description')
    end
  end

  context 'when participants joined' do
    let(:joined) { model::Party.new(phone: '5541977776666', lid: '55443322', push_name: 'Bruno') }
    let(:changes) { model::Events::GroupUpdated::Changes.new(join: [joined]) }

    it 'adds them as members' do
      expect(dispatch).to eq(:handled)

      group_contact = inbox.contacts.find_by(identifier: '120363041234567890@g.us')
      expect(group_contact.group_memberships.active.count).to eq(1)
      expect(group_contact.group_memberships.active.first.contact.name).to eq('Bruno')
    end
  end

  context 'when the inbox number itself was removed' do
    let(:changes) { model::Events::GroupUpdated::Changes.new(leave: [model::Party.new(phone: '5541988887777')]) }

    before do
      with_modified_env WHATSAPP_GROUPS_ENABLED: 'true' do
        Whatsapp::Session::Inbound::Dispatcher.dispatch(
          channel,
          model::Event.build(model::Events::GroupUpdated.new(group: group, actor: actor,
                                                             changes: model::Events::GroupUpdated::Changes.new(subject: 'Equipe')))
        )
      end
    end

    it 'marks the group as left and resolves its threads' do
      expect(dispatch).to eq(:handled)

      group_contact = inbox.contacts.find_by(identifier: '120363041234567890@g.us')
      expect(group_contact.additional_attributes['group_left']).to be(true)
      expect(group_contact.conversations.where(status: %i[open pending])).to be_empty
    end
  end
end
