require 'rails_helper'

RSpec.describe WhatsappGroupMembership do
  let(:account) { create(:account) }
  let(:group) { create(:contact, account: account, group_type: :group, identifier: '120363041234567890@g.us') }
  let(:first_inbox) { create(:inbox, account: account) }
  let(:second_inbox) { create(:inbox, account: account) }

  before do
    create(:contact_inbox, contact: group, inbox: first_inbox, source_id: '120363041234567890')
    create(:contact_inbox, contact: group, inbox: second_inbox, source_id: '120363041234567891')
  end

  it 'leaves the inboxes that stayed in the group' do
    group.mark_group_left!(first_inbox.id)

    expect(group.group_left_in?(first_inbox.id)).to be(true)
    expect(group.group_left_in?(second_inbox.id)).to be(false)
  end

  # The boolean is what every external consumer of the contact payload already reads, so
  # it has to keep meaning something. "Every inbox left" is what it said for the single
  # inbox case, which is nearly all of them.
  it 'only says the group was left once every inbox has left it' do
    group.mark_group_left!(first_inbox.id)

    expect(group.reload.additional_attributes['group_left']).to be(false)

    group.mark_group_left!(second_inbox.id)

    expect(group.reload.additional_attributes['group_left']).to be(true)
  end

  it 'clears the flag for the inbox that rejoined, and leaves the other one alone' do
    group.mark_group_left!(first_inbox.id)
    group.mark_group_left!(second_inbox.id)

    group.mark_group_rejoined!(first_inbox.id)

    expect(group.group_left_in?(first_inbox.id)).to be(false)
    expect(group.group_left_in?(second_inbox.id)).to be(true)
    expect(group.reload.additional_attributes['group_left']).to be(false)
  end

  it 'does not write the same list twice' do
    group.mark_group_left!(first_inbox.id)

    expect { group.mark_group_left!(first_inbox.id) }.not_to(change { group.reload.updated_at })
  end

  # A contact written before the list existed carries the boolean alone, and it was
  # account wide, so it answers for whichever inbox asks until the migration converts it.
  context 'with a contact that predates the list' do
    before { group.update!(additional_attributes: { 'group_left' => true }) }

    it 'reads the old boolean for every inbox' do
      expect(group.group_left_in?(first_inbox.id)).to be(true)
      expect(group.group_left_in?(second_inbox.id)).to be(true)
    end

    it 'converts it the moment one inbox rejoins, without losing the other one' do
      group.mark_group_rejoined!(first_inbox.id)

      expect(group.group_left_in?(first_inbox.id)).to be(false)
      expect(group.group_left_in?(second_inbox.id)).to be(true)
    end
  end
end
