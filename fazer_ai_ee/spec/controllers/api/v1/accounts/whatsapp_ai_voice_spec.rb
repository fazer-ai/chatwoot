require 'rails_helper'

# fazer.ai agents says, for an inbox it is bound to, whether its voice agent answers the inbox's
# calls and the URL their voice is streamed to. Both are written to the inbox's provider_config
# and nothing else in it moves.
RSpec.describe 'WhatsApp voice agent switch', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'native', account: account, validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:stream_url) { 'wss://agents.example.com/api/v1/voice/stream/tok-879' }

  before do
    channel.update!(provider_config: channel.provider_config.merge('session_id' => 'sess-1', 'ai_voice' => { 'note' => 'kept' }))
  end

  def switch(as: admin, account_id: account.id, **body)
    patch "/api/v1/accounts/#{account_id}/whatsapp_calls/ai_voice",
          params: { inbox_id: inbox.id }.merge(body), headers: as.create_new_auth_token, as: :json
  end

  def config = channel.reload.provider_config

  it 'stores the switch and the stream URL, keeping the rest of provider_config' do
    before_config = config

    switch(enabled: true, stream_url: stream_url)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('inbox_id' => inbox.id, 'enabled' => true)
    expect(config['ai_voice']).to eq('note' => 'kept', 'enabled' => true, 'stream_url' => stream_url)
    expect(config.except('ai_voice')).to eq(before_config.except('ai_voice'))
    expect(channel.ai_voice_stream_url).to eq(stream_url)
  end

  it 'replaces the URL, switches off and answers a repeated request the same' do
    switch(enabled: true, stream_url: stream_url)
    switch(enabled: false, stream_url: "#{stream_url}b")
    after_first = config

    switch(enabled: false, stream_url: "#{stream_url}b")

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq('inbox_id' => inbox.id, 'enabled' => false)
    expect(config).to eq(after_first)
    expect(config['ai_voice']).to include('enabled' => false, 'stream_url' => "#{stream_url}b")
    expect(channel.ai_voice_stream_url).to be_nil
  end

  it 'switches on again with the URL it kept' do
    switch(enabled: true, stream_url: stream_url)
    switch(enabled: false)
    switch(enabled: true)

    expect(response).to have_http_status(:ok)
    expect(channel.reload.ai_voice_stream_url).to eq(stream_url)
  end

  # The design before this one derived the URL from the inbox's Agent Bot. The call does not go
  # through the bot, and an inbox with a bot and no URL has nothing to stream to.
  it 'does not take the URL from the inbox agent bot' do
    bot = create(:agent_bot, account: account, outgoing_url: 'https://agents.example.com/api/v1/chatwoot/webhook/tok-bot')
    create(:agent_bot_inbox, inbox: inbox, agent_bot: bot)

    switch(enabled: true)

    expect(response).to have_http_status(:unprocessable_entity)
    expect(channel.reload.ai_voice_stream_url).to be_nil
  end

  it 'refuses a URL that is not a WebSocket one, writing nothing' do
    before_config = config

    ['isto nao e uma url', 'ftp://agents.example.com/voice', 'https://agents.example.com/voice', 'wss://'].each do |url|
      switch(enabled: true, stream_url: url)

      expect(response).to have_http_status(:unprocessable_entity), url
    end
    expect(config).to eq(before_config)
  end

  it 'refuses an enabled that is not a JSON boolean, writing nothing' do
    switch(enabled: true, stream_url: stream_url)
    before_config = config

    ['disabled', 'false', 2, nil, { value: false }].each do |value|
      switch(enabled: value, stream_url: "#{stream_url}x")

      expect(response).to have_http_status(:unprocessable_entity), value.inspect
    end
    expect(config).to eq(before_config)
  end

  # A dashboard holding the old provider_config writes it back whole on its next settings save.
  it 'invalidates the account inbox cache' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch).and_call_original

    switch(enabled: true, stream_url: stream_url)

    invalidated = [Events::Types::ACCOUNT_CACHE_INVALIDATED, anything, hash_including(account: account)]
    expect(Rails.configuration.dispatcher).to have_received(:dispatch).with(*invalidated).at_least(:once)
  end

  it 'refuses an agent who is not an administrator' do
    switch(as: agent, enabled: true, stream_url: stream_url)

    expect(response).to have_http_status(:unauthorized)
    expect(channel.reload.ai_voice_stream_url).to be_nil
  end

  it 'refuses an administrator of another account' do
    outsider = create(:user, account: create(:account), role: :administrator)

    switch(as: outsider, enabled: true, stream_url: stream_url)

    expect(response).to have_http_status(:unauthorized)
    expect(channel.reload.ai_voice_stream_url).to be_nil
  end

  it 'does not find an inbox of another account' do
    other = create(:channel_whatsapp, provider: 'native', account: create(:account), validate_provider_config: false, sync_templates: false)

    patch "/api/v1/accounts/#{account.id}/whatsapp_calls/ai_voice",
          params: { inbox_id: other.inbox.id, enabled: true, stream_url: stream_url }, headers: admin.create_new_auth_token, as: :json

    expect(response).to have_http_status(:not_found)
    expect(other.reload.provider_config).not_to have_key('ai_voice')
  end

  it 'refuses an inbox that does not carry calls through the connector' do
    cloud = create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account, validate_provider_config: false, sync_templates: false)

    [create(:inbox, account: account), cloud.inbox].each do |other|
      patch "/api/v1/accounts/#{account.id}/whatsapp_calls/ai_voice",
            params: { inbox_id: other.id, enabled: true, stream_url: stream_url }, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end
    expect(cloud.reload.provider_config).not_to have_key('ai_voice')
  end
end
