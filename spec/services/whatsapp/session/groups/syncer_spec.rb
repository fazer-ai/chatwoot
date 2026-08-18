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

  # The settings are optional on the wire. A snapshot that does not report one says
  # nothing about it, and a sync must not read that silence as "off".
  context 'when the snapshot reports no settings at all' do
    let(:stored) { super().merge('announce' => true, 'restrict' => true) }

    it 'leaves the stored ones alone' do
      sync

      expect(group_contact.reload.additional_attributes).to include('announce' => true, 'restrict' => true)
    end
  end

  context 'when the snapshot reports a setting off' do
    let(:stored) { super().merge('announce' => true) }
    let(:info) { model::GroupInfo.new(group: group, subject: 'Equipe', announce: false) }

    it 'turns it off' do
      sync

      expect(group_contact.reload.additional_attributes['announce']).to be(false)
    end
  end

  # Only rejoining clears the flag, and only `group.joined` knows that happened. A
  # scheduled sync can still read cached metadata for a group the session left, and
  # clearing it there would put the group actions back for a thread that cannot send.
  context 'when the group was already left and the sync fetched its metadata' do
    subject(:fetched_sync) { described_class.new(channel: channel, group_contact: group_contact).perform }

    let(:stored) { super().merge('group_left' => true) }
    let(:backend) { Whatsapp::Session::Backends::Fake.new(channel) }

    before { allow(channel).to receive(:provider_service).and_return(backend) }

    it 'keeps the group marked as left' do
      fetched_sync

      expect(group_contact.reload.additional_attributes['group_left']).to be(true)
    end
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
