require 'rails_helper'

describe Channels::Whatsapp::BaileysHistoryImportFinalizeJob do
  let(:channel) do
    create(:channel_whatsapp,
           provider: 'baileys',
           provider_config: { history_import_days: 7 },
           validate_provider_config: false,
           sync_templates: false)
  end

  context 'when no history_import snapshot exists' do
    it 'no-ops without raising' do
      expect { described_class.perform_now(channel.id) }.not_to raise_error
      expect(channel.reload.history_import_state).to be_nil
    end
  end

  context 'when the channel was deleted before the watchdog fired' do
    it 'no-ops without raising' do
      expect { described_class.perform_now(channel.id + 999) }.not_to raise_error
    end
  end

  context 'when the import is already completed' do
    it 'leaves the state untouched' do
      channel.update_history_import_state!(
        status: 'completed',
        finished_at: 1.minute.ago.iso8601,
        messages_imported: 100
      )
      original = channel.reload.history_import_state

      described_class.perform_now(channel.id)

      expect(channel.reload.history_import_state).to eq(original)
    end
  end

  context 'when a batch landed recently (within the idle window)' do
    it 'leaves status as in_progress so a later watchdog can finalize' do
      channel.update_history_import_state!(
        status: 'in_progress',
        last_batch_at: 5.seconds.ago.iso8601,
        messages_imported: 100
      )

      described_class.perform_now(channel.id)

      state = channel.reload.history_import_state
      expect(state['status']).to eq('in_progress')
      expect(state['finished_at']).to be_nil
    end
  end

  context 'when the last batch is older than the idle window' do
    it 'marks the import as completed and stamps finished_at' do
      idle_window = Whatsapp::IncomingMessageBaileysService::HISTORY_IMPORT_IDLE_WINDOW
      channel.update_history_import_state!(
        status: 'in_progress',
        last_batch_at: (idle_window + 30.seconds).ago.iso8601,
        messages_imported: 1_559
      )

      described_class.perform_now(channel.id)

      state = channel.reload.history_import_state
      expect(state['status']).to eq('completed')
      expect(state['finished_at']).to be_present
      expect(state['messages_imported']).to eq(1_559)
    end
  end
end
