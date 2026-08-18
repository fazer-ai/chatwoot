require 'rails_helper'

RSpec.describe Whatsapp::Session::Inbound::Handlers::GroupActivity do
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
  let(:event) { model::Event.build(model::Events::GroupActivity.new(groups: [group])) }

  it 'is ignored while the group capability is off' do
    expect(Whatsapp::Session::Inbound::Dispatcher.dispatch(channel, event)).to eq(:ignored)
  end

  it 'opens the group and moves its card up the chat list' do
    expect(dispatch).to eq(:handled)

    group_contact = inbox.contacts.find_by(identifier: '120363041234567890@g.us')
    expect(group_contact.conversations.last.last_activity_at).to be_present
  end

  # Without the originating channel the service falls back to `Contact#group_channel`,
  # which picks the group contact's first contact_inbox: an arbitrary choice as soon as
  # the same group is in two inboxes, and the sync can run through a session that is not
  # connected while the one that saw the activity stays stale.
  it 'asks for the soft sync on the inbox that saw the activity' do
    dispatch

    expect(Contacts::SyncGroupJob).to have_been_enqueued.with(anything, soft: true, channel: channel)
  end
end
