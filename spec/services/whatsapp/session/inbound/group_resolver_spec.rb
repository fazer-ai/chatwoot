require 'rails_helper'

RSpec.describe Whatsapp::Session::Inbound::GroupResolver do
  subject(:resolve) { described_class.new(inbox: inbox, group: group, sender: sender, subject: 'Equipe de Vendas').perform }

  let(:channel) do
    create(:channel_whatsapp, provider: 'native', phone_number: '+5541988887777',
                              validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:model) { Whatsapp::Session::Model }
  let(:group) { model::Address.group('120363041234567890') }
  let(:sender) { model::Party.new(phone: '5541999990000', lid: '182736451928374', push_name: 'Ana Souza') }

  it 'files the sender as a member of the group' do
    result = resolve

    member = GroupMember.find_by(group_contact: result.group_contact, contact: result.sender_contact)
    expect(member).to have_attributes(role: 'member', is_active: true)
  end

  # A message says who wrote it, never what they are in the group. Writing the default
  # role here demoted an administrator on every message they sent, and `inbox_admin?` is
  # what decides whether this inbox may post in an announce-only group.
  it 'keeps a role a roster sync or a promotion already recorded' do
    first = resolve
    GroupMember.find_by(group_contact: first.group_contact, contact: first.sender_contact).update!(role: :admin)

    result = described_class.new(inbox: inbox, group: group, sender: sender).perform

    expect(GroupMember.find_by(group_contact: result.group_contact, contact: result.sender_contact).role).to eq('admin')
  end

  it 'reactivates a member who had left and came back' do
    first = resolve
    GroupMember.find_by(group_contact: first.group_contact, contact: first.sender_contact)
               .update!(role: :admin, is_active: false)

    result = described_class.new(inbox: inbox, group: group, sender: sender).perform

    expect(GroupMember.find_by(group_contact: result.group_contact, contact: result.sender_contact))
      .to have_attributes(role: 'admin', is_active: true)
  end
end
