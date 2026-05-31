require 'rails_helper'

describe Disparos::RulesConfig do
  describe 'defaults (no account / no settings)' do
    # nil account, an account with no settings, and an account whose settings hold
    # no disparador_settings sub-hash must ALL resolve to the original hardcoded
    # bindings — this is the behavior-preserving anchor.
    shared_examples 'the original default bindings' do
      it 'returns the original constants', :aggregate_failures do
        expect(config.opt_out_label).to eq('agente-off-permanente')
        expect(config.kanban_opt_out_steps).to eq(['9'])
        expect(config.opt_out_lgpd_key).to eq('opt_out_lgpd')
        expect(config.followup_locked_key).to eq('followup_locked')
        expect(config.window_closes_at_key).to eq('window_closes_at')
        expect(config.kanban_step_key).to eq('kanban_step')
        expect(config.whatsapp_invalid_at_key).to eq('whatsapp_invalid_at')
        expect(config.dedup_window).to eq(7.days)
        expect(config.whatsapp_invalid_window).to eq(30.days)
      end
    end

    context 'with a nil account' do
      let(:config) { described_class.new }

      it_behaves_like 'the original default bindings'
    end

    context 'with an account that has no disparador_settings' do
      let(:config) { described_class.new(create(:account)) }

      it_behaves_like 'the original default bindings'
    end
  end

  describe 'overrides' do
    let(:account) { create(:account) }

    it 'returns the account-configured bindings' do
      account.update!(disparador_settings: {
                        'opt_out_label' => 'No-Contact',
                        'kanban_opt_out_steps' => [7, '8'],
                        'opt_out_lgpd_key' => 'gdpr_opt_out',
                        'dedup_window_days' => 14,
                        'whatsapp_invalid_window_days' => 60
                      })
      config = described_class.new(account)

      expect(config.opt_out_label).to eq('No-Contact')
      expect(config.kanban_opt_out_steps).to eq(%w[7 8])
      expect(config.opt_out_lgpd_key).to eq('gdpr_opt_out')
      expect(config.dedup_window).to eq(14.days)
      expect(config.whatsapp_invalid_window).to eq(60.days)
    end

    it 'falls back to defaults for keys the partial config omits' do
      account.update!(disparador_settings: { 'opt_out_label' => 'No-Contact' })
      config = described_class.new(account)

      expect(config.opt_out_label).to eq('No-Contact')
      expect(config.kanban_opt_out_steps).to eq(['9'])
      expect(config.dedup_window).to eq(7.days)
    end

    it 'ignores a blank/non-positive window override and keeps the default' do
      account.update!(disparador_settings: { 'dedup_window_days' => 0 })
      config = described_class.new(account)

      expect(config.dedup_window).to eq(7.days)
    end
  end
end
