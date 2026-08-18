require 'rails_helper'

RSpec.describe Whatsapp::Session::Groups::Syncer do
  subject(:sync) { described_class.new(channel: channel, group_contact: group_contact, info: info).perform }

  let(:channel) do
    create(:channel_whatsapp, provider: 'native', phone_number: '+5541988887777',
                              validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:model) { Whatsapp::Session::Model }
  let(:group) { model::Address.group('120363041234567890') }
  let(:group_contact) do
    create(:contact, account: channel.account, identifier: '120363041234567890@g.us', group_type: :group,
                     additional_attributes: stored)
  end
  let(:stored) do
    { 'description' => 'Combinados do time', 'invite_code' => 'OLDCODE', 'owner_pn' => '5541999990000' }
  end
  let(:info) { model::GroupInfo.new(group: group, subject: 'Equipe de Vendas') }

  before { create(:contact_inbox, inbox: inbox, contact: group_contact, source_id: '120363041234567890') }

  it 'brings the name in line with what the provider reports' do
    sync

    expect(group_contact.reload.name).to eq('Equipe de Vendas')
  end

  # A snapshot describes the group as it is now, so a description the group removed has
  # to overwrite the stored one. Dropping the empty value would leave the old text on
  # screen with no way to ever clear it.
  context 'when the group removed its description' do
    let(:info) { model::GroupInfo.new(group: group, subject: 'Equipe de Vendas', description: '') }

    it 'clears it' do
      sync

      expect(group_contact.reload.additional_attributes['description']).to be_nil
    end
  end

  # An absent field is not a removal: the invite code is only readable by an admin, so
  # a sync run by a member must not throw away the code we already have.
  it 'keeps what the snapshot does not describe' do
    sync

    expect(group_contact.reload.additional_attributes).to include(
      'description' => 'Combinados do time', 'invite_code' => 'OLDCODE'
    )
  end

  context 'when only admins may add people' do
    let(:info) { model::GroupInfo.new(group: group, subject: 'Equipe', member_add_mode: 'admin_add') }

    it 'stores the setting as the boolean the dashboard reads' do
      sync

      expect(group_contact.reload.additional_attributes['member_add_mode']).to be(false)
    end
  end

  context 'when every member may add people' do
    let(:info) { model::GroupInfo.new(group: group, subject: 'Equipe', member_add_mode: 'all_member_add') }

    it 'stores it as enabled' do
      sync

      expect(group_contact.reload.additional_attributes['member_add_mode']).to be(true)
    end
  end
end
