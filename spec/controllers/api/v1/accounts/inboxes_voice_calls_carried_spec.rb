require 'rails_helper'

# The dashboard reads this to say why calls are unavailable on a paired inbox, instead of
# offering a switch and buttons whose every call fails for want of the connector's UDP port.
RSpec.describe 'Inbox payload: whether the connector carries call voice', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:channel) do
    create(:channel_whatsapp, account: account, provider: 'native', validate_provider_config: false, sync_templates: false)
  end

  def payload_for(inbox)
    get "/api/v1/accounts/#{account.id}/inboxes/#{inbox.id}", headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:success)
    response.parsed_body
  end

  it 'says what the connector announces for a paired inbox' do
    allow(Whatsapp::Connector::Client).to receive(:carries_calls?).and_return(false)
    expect(payload_for(channel.inbox)['voice_calls_carried']).to be(false)

    allow(Whatsapp::Connector::Client).to receive(:carries_calls?).and_return(true)
    expect(payload_for(channel.inbox)['voice_calls_carried']).to be(true)
  end

  it 'leaves the field out of a Cloud inbox, which calls through Meta' do
    cloud = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
    allow(Whatsapp::Connector::Client).to receive(:carries_calls?)

    expect(payload_for(cloud.inbox)).not_to have_key('voice_calls_carried')
    expect(Whatsapp::Connector::Client).not_to have_received(:carries_calls?)
  end
end
