require 'rails_helper'

# Covers the `importMode: true` backfill path: live-only side effects are
# suppressed, conversations open as resolved, no read receipts go back to the
# device, and the channel's provider_connection['history_import'] snapshot
# tracks per-batch progress.
describe Whatsapp::IncomingMessageBaileysService, type: :service do
  let(:webhook_verify_token) { 'valid_token' }
  let!(:whatsapp_channel) do
    create(:channel_whatsapp,
           provider: 'baileys',
           provider_config: { webhook_verify_token: webhook_verify_token, history_import_days: 7 },
           validate_provider_config: false,
           received_messages: false)
  end
  let(:inbox) { whatsapp_channel.inbox }
  let(:timestamp) { Time.current.to_i }
  let(:raw_message) do
    {
      key: { id: 'history_msg_1', remoteJid: '5511999999999@s.whatsapp.net', fromMe: false },
      pushName: 'Old Contact',
      messageTimestamp: timestamp - (3 * 86_400),
      message: { conversation: 'Hi from last week' }
    }
  end
  let(:base_params) do
    {
      webhookVerifyToken: webhook_verify_token,
      event: 'messages.upsert',
      importMode: true,
      importBatch: { index: 0, total: 1, phase: 'history' },
      data: { type: 'notify', messages: [raw_message] }
    }
  end

  before do
    stub_request(:get, /profile-picture-url/)
      .to_return(status: 200, body: { data: { profilePictureUrl: nil } }.to_json)
    Current.reset
  end

  after { Current.reset }

  it 'creates the conversation as resolved' do
    described_class.new(inbox: inbox, params: base_params).perform

    conversation = inbox.conversations.last
    expect(conversation).to be_present
    expect(conversation.status).to eq('resolved')
  end

  it 'does not dispatch MESSAGE_CREATED or PROVIDER_EVENT_RECEIVED' do
    allow(Rails.configuration.dispatcher).to receive(:dispatch)

    described_class.new(inbox: inbox, params: base_params).perform

    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
      .with(Events::Types::PROVIDER_EVENT_RECEIVED, anything, anything)
    expect(Rails.configuration.dispatcher).not_to have_received(:dispatch)
      .with(Events::Types::MESSAGE_CREATED, anything, anything)
  end

  it 'does not send read receipts back to the device' do
    allow(whatsapp_channel).to receive(:received_messages)
    allow(inbox).to receive(:channel).and_return(whatsapp_channel)

    described_class.new(inbox: inbox, params: base_params).perform

    expect(whatsapp_channel).not_to have_received(:received_messages)
  end

  it 'updates the channel history_import snapshot per batch' do
    described_class.new(inbox: inbox, params: base_params).perform

    state = whatsapp_channel.reload.history_import_state
    # Status stays `in_progress` until the watchdog flips it — Baileys can
    # keep firing `messaging-history.set` after the supposed "last" batch.
    expect(state['status']).to eq('in_progress')
    expect(state['processed_batches']).to eq(1)
    expect(state['messages_imported']).to eq(1)
    expect(state['started_at']).to be_present
    expect(state['last_batch_at']).to be_present
    expect(state['finished_at']).to be_nil
  end

  it 'accumulates messages_imported across multiple history events' do
    described_class.new(inbox: inbox, params: base_params).perform
    described_class.new(inbox: inbox, params: base_params.merge(
      data: { type: 'notify', messages: [raw_message.merge(key: { id: 'history_msg_2', remoteJid: raw_message[:key][:remoteJid], fromMe: false })] }
    )).perform

    state = whatsapp_channel.reload.history_import_state
    expect(state['processed_batches']).to eq(2)
    expect(state['messages_imported']).to eq(2)
    expect(state['status']).to eq('in_progress')
  end

  it 'schedules a watchdog job to finalize the import after the idle window' do
    expect do
      described_class.new(inbox: inbox, params: base_params).perform
    end.to have_enqueued_job(Channels::Whatsapp::BaileysHistoryImportFinalizeJob)
      .with(whatsapp_channel.id)
  end

  it 'resets Current.history_import after perform so subsequent live events behave normally' do
    described_class.new(inbox: inbox, params: base_params).perform

    expect(Current.history_import).to be_nil
  end

  context 'without importMode' do
    it 'does not touch the history_import snapshot' do
      live_params = base_params.except(:importMode, :importBatch)

      described_class.new(inbox: inbox, params: live_params).perform

      expect(whatsapp_channel.reload.history_import_state).to be_nil
    end
  end

  context 'when a connection.update event arrives mid-import' do
    # Regression: `update_provider_connection!` replaces the JSONB, so the
    # connection_update handler used to wipe `history_import` every time the
    # node service emitted a state change. The card kept appearing then
    # vanishing in dev because Baileys re-emits connection_update events
    # for typing/QR rotation/reconnect.
    it 'preserves the history_import snapshot across connection state changes' do
      described_class.new(inbox: inbox, params: base_params).perform
      expect(whatsapp_channel.reload.history_import_state).to be_present

      connection_params = {
        webhookVerifyToken: webhook_verify_token,
        event: 'connection.update',
        data: { connection: 'open' }
      }
      described_class.new(inbox: inbox, params: connection_params).perform

      state = whatsapp_channel.reload.history_import_state
      expect(state).to be_present
      expect(state['status']).to eq('in_progress')
      expect(state['messages_imported']).to eq(1)
    end
  end
end
