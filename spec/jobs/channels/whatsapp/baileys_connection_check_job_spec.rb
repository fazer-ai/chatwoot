require 'rails_helper'

RSpec.describe Channels::Whatsapp::BaileysConnectionCheckJob do
  let(:channel_whatsapp) { create(:channel_whatsapp, provider: 'baileys', sync_templates: false, validate_provider_config: false) }
  let(:provider_service) { instance_double(Whatsapp::Providers::WhatsappBaileysService) }

  before do
    allow(channel_whatsapp).to receive_messages(setup_channel_provider: true, provider_service: provider_service)
    allow(provider_service).to receive_messages(fetch_reachout_timelock: nil, fetch_new_chat_cap: nil)
  end

  it 'enqueues the job' do
    expect { described_class.perform_later(channel_whatsapp) }.to have_enqueued_job(described_class)
      .on_queue('low')
  end

  context 'when called' do
    it 'calls setup_channel_provider' do
      described_class.perform_now(channel_whatsapp)

      expect(channel_whatsapp).to have_received(:setup_channel_provider)
    end

    it 'persists the fetched reach-out time-lock' do
      lock = { is_active: true, time_enforcement_ends: '2026-06-19T21:52:39.000Z' }
      allow(provider_service).to receive(:fetch_reachout_timelock).and_return(lock)
      allow(channel_whatsapp).to receive(:update_reachout_time_lock!)

      described_class.perform_now(channel_whatsapp)

      expect(channel_whatsapp).to have_received(:update_reachout_time_lock!).with(lock)
    end

    it 'persists the fetched new-chat cap' do
      cap = { capping_status: 'CAPPED', total_quota: 100, used_quota: 100 }
      allow(provider_service).to receive(:fetch_new_chat_cap).and_return(cap)
      allow(channel_whatsapp).to receive(:update_new_chat_cap!)

      described_class.perform_now(channel_whatsapp)

      expect(channel_whatsapp).to have_received(:update_new_chat_cap!).with(cap)
    end

    it 'skips persistence when a fetch returns nil (unknown / 404)' do
      allow(channel_whatsapp).to receive(:update_reachout_time_lock!)
      allow(channel_whatsapp).to receive(:update_new_chat_cap!)

      described_class.perform_now(channel_whatsapp)

      expect(channel_whatsapp).not_to have_received(:update_reachout_time_lock!)
      expect(channel_whatsapp).not_to have_received(:update_new_chat_cap!)
    end

    it 'does not let a cap fetch error abort the connection check' do
      allow(provider_service).to receive(:fetch_new_chat_cap).and_raise(StandardError, 'boom')

      expect { described_class.perform_now(channel_whatsapp) }.not_to raise_error
      expect(channel_whatsapp).to have_received(:setup_channel_provider)
    end
  end
end
