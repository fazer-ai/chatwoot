require 'rails_helper'

# A group contact is account-scoped, so one WhatsApp group can belong to two inboxes of
# the same account. Every group action used to resolve its channel by taking whichever
# contact inbox came first, while the dashboard decided what the agent may do from the
# inbox they had open: the panel granted the action using one inbox's capabilities and
# admin status, and the server performed it as another. Leaving is the worst of them,
# because it removes the wrong number from the group.
#
# Asserted on `group_admin#leave`, which is the destructive one, and on the ambiguity
# itself, which every group endpoint answers the same way through the shared concern.
RSpec.describe 'group actions and the inbox they run as', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:looking_at) do
    create(:channel_whatsapp, provider: 'baileys', validate_provider_config: false, sync_templates: false, account: account)
  end
  let(:other) do
    create(:channel_whatsapp, provider: 'baileys', validate_provider_config: false, sync_templates: false, account: account)
  end
  let(:group_contact) { create(:contact, account: account, group_type: :group, identifier: '120363041234567890@g.us') }

  before do
    # `other` first, so taking whichever comes first is the wrong answer.
    create(:contact_inbox, contact: group_contact, inbox: other.inbox, source_id: '120363041234567890')
    create(:contact_inbox, contact: group_contact, inbox: looking_at.inbox, source_id: '120363041234567890')
  end

  it 'leaves the group as the inbox the caller named' do
    left_as = []
    allow(Whatsapp::Providers::WhatsappBaileysService).to receive(:new) do |whatsapp_channel:|
      instance_double(Whatsapp::Providers::WhatsappBaileysService).tap do |service|
        allow(service).to receive(:group_leave) { left_as << whatsapp_channel }
      end
    end

    post "/api/v1/accounts/#{account.id}/contacts/#{group_contact.id}/group_admin/leave",
         params: { inbox_id: looking_at.inbox.id }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
    expect(left_as).to eq([looking_at])
  end

  it 'refuses an inbox this group is not in' do
    stranger = create(:channel_whatsapp, provider: 'baileys', validate_provider_config: false, sync_templates: false,
                                         account: account)

    post "/api/v1/accounts/#{account.id}/contacts/#{group_contact.id}/group_admin/leave",
         params: { inbox_id: stranger.inbox.id }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  it 'refuses to guess when the caller names none' do
    post "/api/v1/accounts/#{account.id}/contacts/#{group_contact.id}/group_admin/leave",
         headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:bad_request)
  end

  # `ContactPolicy` lets every agent of the account read and update a contact, which was
  # harmless while the inbox was ours to pick. Naming one is a request, so without this an
  # agent on one inbox could leave the group, promote or remove members as another.
  it 'refuses an inbox the agent is not on' do
    agent = create(:user, account: account, role: :agent)
    create(:inbox_member, user: agent, inbox: looking_at.inbox)

    post "/api/v1/accounts/#{account.id}/contacts/#{group_contact.id}/group_admin/leave",
         params: { inbox_id: other.inbox.id }, headers: agent.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
  end

  # The endpoints predate the parameter and are documented without it, so a group that is
  # in one inbox still answers on its own.
  it 'needs no inbox when the group is in only one' do
    group_contact.contact_inboxes.where(inbox: other.inbox).destroy_all
    service = instance_double(Whatsapp::Providers::WhatsappBaileysService, group_leave: true)
    allow(Whatsapp::Providers::WhatsappBaileysService).to receive(:new).and_return(service)

    post "/api/v1/accounts/#{account.id}/contacts/#{group_contact.id}/group_admin/leave",
         headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:ok)
  end
end
