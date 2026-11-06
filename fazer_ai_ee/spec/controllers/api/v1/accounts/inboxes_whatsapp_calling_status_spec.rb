require 'rails_helper'

# Read live by the calling settings: served with the cached inbox payload, a "no call
# port" from before a redeploy would keep calls blocked after the deployment was fixed.
RSpec.describe 'GET whatsapp_calling_status', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'native', validate_provider_config: false, sync_templates: false)
  end

  def status_of(inbox, user = admin)
    get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}/whatsapp_calling_status", headers: user.create_new_auth_token, as: :json
  end

  it 'says what the connector announces right now for a paired inbox' do
    allow(Whatsapp::Connector::Client).to receive(:carries_calls?).and_return(false)
    status_of(channel.inbox)
    expect(response.parsed_body).to eq('voice_calls_carried' => false)

    allow(Whatsapp::Connector::Client).to receive(:carries_calls?).and_return(true)
    status_of(channel.inbox)
    expect(response.parsed_body).to eq('voice_calls_carried' => true)
  end

  it 'answers true for a Cloud inbox without asking the connector' do
    cloud = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
    allow(Whatsapp::Connector::Client).to receive(:carries_calls?)

    status_of(cloud.inbox)

    expect(response.parsed_body).to eq('voice_calls_carried' => true)
    expect(Whatsapp::Connector::Client).not_to have_received(:carries_calls?)
  end

  it 'is for administrators' do
    create(:inbox_member, user: agent, inbox: channel.inbox)
    status_of(channel.inbox, agent)

    expect(response).to have_http_status(:unauthorized)
  end
end
