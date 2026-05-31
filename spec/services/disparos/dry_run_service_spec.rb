require 'rails_helper'

describe Disparos::DryRunService do
  subject(:service) { described_class.new(now: now) }

  let(:account) { create(:account) }
  let(:cloud_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:cloud_inbox) { cloud_channel.inbox }
  # The factory's default message_templates approve this name (status 'approved'),
  # so every factory-built cloud inbox is on the per-template allowlist (G4).
  let(:template_name) { 'sample_shipping_confirmation' }
  let(:now) { Time.zone.parse('2026-05-29 12:00:00') }
  let(:filter) { { 'kanban_steps' => %w[3], 'label' => ['vip'] } }

  let(:disparo) do
    disparo = create(:disparo, account: account, template_name: template_name, audience_filter: filter)
    create(:disparo_inbox, disparo: disparo, inbox: cloud_inbox)
    disparo
  end

  # Candidate matching the filter (Stage 3 + label vip) on the cloud inbox.
  def candidate(custom_attributes: {}, contact: nil, label_list: ['vip'])
    attrs = custom_attributes.merge('kanban_step' => '3')
    convo_attrs = { account: account, inbox: cloud_inbox, custom_attributes: attrs, label_list: label_list }
    convo_attrs[:contact] = contact if contact
    create(:conversation, **convo_attrs)
  end

  describe '#perform' do
    context 'when the disparo is not runnable for dry-run' do
      it 'raises InvalidDryRun when template_name is blank' do
        disparo.update!(template_name: nil)

        expect { service.perform(disparo) }.to raise_error(CustomExceptions::Disparos::InvalidDryRun)
      end

      it 'raises InvalidDryRun when there is no disparo_inbox' do
        bare = create(:disparo, account: account, template_name: template_name, audience_filter: filter)

        expect { service.perform(bare) }.to raise_error(CustomExceptions::Disparos::InvalidDryRun)
      end

      it 'raises InvalidDryRun when the audience filter has neither kanban_steps nor label' do
        disparo.update!(audience_filter: {})

        expect { service.perform(disparo) }.to raise_error(CustomExceptions::Disparos::InvalidDryRun)
      end
    end

    context 'with a kanban_step + label filter (AC3/AC4)' do
      it 'returns eligible/skipped counts and a skip-reason breakdown' do
        candidate(contact: create(:contact, account: account, phone_number: '+5511999998888'))
        opted_out = create(:contact, account: account, phone_number: '+5511988887777')
        candidate(contact: opted_out, custom_attributes: { 'opt_out_lgpd' => true })

        summary = service.perform(disparo)

        expect(summary.total_eligible).to eq(1)
        expect(summary.total_skipped).to eq(1)
        expect(summary.by_skip_reason).to eq('opt_out_lgpd' => 1)
        expect(summary.by_inbox).to eq(cloud_inbox.id.to_s => 1)
      end
    end

    # wf15 reconciliation: the audience is scoped to the disparo's SELECTED
    # inboxes. A matching candidate on a cloud inbox that is NOT selected never
    # enters the audience (it is absent, not counted as skipped).
    context 'when a matching candidate is on a cloud inbox the disparo did NOT select' do
      it 'excludes it from the audience entirely (not eligible, not skipped)', :aggregate_failures do
        other_inbox = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                                sync_templates: false, validate_provider_config: false).inbox
        # Selected-inbox candidate (eligible).
        candidate(contact: create(:contact, account: account, phone_number: '+5511999990001'))
        # Otherwise-matching candidate on the UNSELECTED inbox.
        create(:conversation, account: account, inbox: other_inbox, custom_attributes: { 'kanban_step' => '3' },
                              label_list: ['vip'], contact: create(:contact, account: account, phone_number: '+5511999990002'))

        summary = service.perform(disparo)

        expect(summary.total_eligible).to eq(1)
        expect(summary.total_skipped).to eq(0)
        expect(summary.by_inbox).to eq(cloud_inbox.id.to_s => 1)
      end
    end

    # wf15 reconciliation: the disparo's conversation_status gates the audience.
    context 'with the conversation_status gate (open vs all)' do
      it "with conversation_status 'open' excludes a resolved candidate that otherwise matches", :aggregate_failures do
        candidate(contact: create(:contact, account: account, phone_number: '+5511999990001'))
        resolved = candidate(contact: create(:contact, account: account, phone_number: '+5511999990002'))
        resolved.update!(status: :resolved)

        summary = service.perform(disparo) # disparo defaults conversation_status to open

        expect(summary.total_eligible).to eq(1)
        expect(summary.total_skipped).to eq(0)
      end

      it "with conversation_status 'all' includes the resolved candidate" do
        candidate(contact: create(:contact, account: account, phone_number: '+5511999990001'))
        resolved = candidate(contact: create(:contact, account: account, phone_number: '+5511999990002'))
        resolved.update!(status: :resolved)
        disparo.update!(conversation_status: :all)

        summary = service.perform(disparo)

        expect(summary.total_eligible).to eq(2)
      end
    end

    context 'when eligible candidates span TWO cloud inboxes (by_inbox groups by inbox_id)' do
      it 'counts eligible candidates per inbox_id (inbox_a => 2, inbox_b => 1)', :aggregate_failures do
        inbox_b = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                            sync_templates: false, validate_provider_config: false).inbox
        create(:disparo_inbox, disparo: disparo, inbox: inbox_b)

        # Two eligible candidates on inbox_a (the default cloud_inbox).
        candidate(contact: create(:contact, account: account, phone_number: '+5511999990001'))
        candidate(contact: create(:contact, account: account, phone_number: '+5511999990002'))

        # One eligible candidate on inbox_b — same Stage 3 + vip filter, distinct valid phone.
        create(:conversation, account: account, inbox: inbox_b, custom_attributes: { 'kanban_step' => '3' },
                              label_list: ['vip'], contact: create(:contact, account: account, phone_number: '+5511999990003'))

        summary = service.perform(disparo)

        expect(summary.total_eligible).to eq(3)
        expect(summary.total_skipped).to eq(0)
        expect(summary.by_inbox).to eq(cloud_inbox.id.to_s => 2, inbox_b.id.to_s => 1)
      end
    end

    context 'when a candidate fails multiple rules (AC44 counts ALL skip_reasons)' do
      it 'increments BOTH buckets for an invalid_phone + opt_out_lgpd candidate' do
        bad_phone = build(:contact, account: account, phone_number: '12345')
        bad_phone.save!(validate: false)
        candidate(contact: bad_phone, custom_attributes: { 'opt_out_lgpd' => true })

        summary = service.perform(disparo)

        expect(summary.total_eligible).to eq(0)
        expect(summary.total_skipped).to eq(1)
        expect(summary.by_skip_reason).to eq('invalid_phone' => 1, 'opt_out_lgpd' => 1)
      end
    end

    context 'with cost estimation' do
      it 'returns nil estimated_cost_cents when the estimator is unconfigured (unknown_price)' do
        candidate(contact: create(:contact, account: account, phone_number: '+5511999998888'))

        summary = service.perform(disparo)

        expect(summary.estimated_cost_cents).to be_nil
        expect(summary.snapshot.estimated_cost_cents).to be_nil
      end

      it 'returns an integer estimated_cost_cents keyed by template_category when an estimator is configured' do
        candidate(contact: create(:contact, account: account, phone_number: '+5511999998888'))
        # The disparo factory defaults template_category to utility; the cost table
        # is keyed by category (matching CostEstimator), NOT by template_name.
        estimator = Disparos::CostEstimator.new(prices: { 'utility' => 9 }, source: 'meta_pricelist_2026q2')

        summary = described_class.new(now: now, cost_estimator: estimator).perform(disparo)

        expect(summary.total_eligible).to eq(1)
        expect(summary.estimated_cost_cents).to eq(9)
        expect(summary.snapshot.estimated_cost_cents).to eq(9)
        expect(summary.cost_source).to eq('meta_pricelist_2026q2')
      end

      it 'reports unknown_price when the table is keyed by template_name instead of category' do
        candidate(contact: create(:contact, account: account, phone_number: '+5511999998888'))
        # A table keyed by template_name no longer resolves: the service passes the
        # category, so a name-keyed price misses and falls back to unknown_price.
        estimator = Disparos::CostEstimator.new(prices: { template_name => 9 }, source: 'meta_pricelist_2026q2')

        summary = described_class.new(now: now, cost_estimator: estimator).perform(disparo)

        expect(summary.estimated_cost_cents).to be_nil
      end
    end

    context 'when persisting the aggregate snapshot' do
      it 'creates ONE aggregate DisparoAudienceSnapshot row with the breakdowns and expiry', :aggregate_failures do
        candidate(contact: create(:contact, account: account, phone_number: '+5511999998888'))
        opted_out = create(:contact, account: account, phone_number: '+5511988887777')
        candidate(contact: opted_out, custom_attributes: { 'opt_out_lgpd' => true })

        expect { service.perform(disparo) }.to change(DisparoAudienceSnapshot, :count).by(1)

        snapshot = DisparoAudienceSnapshot.last
        expect(snapshot.disparo_id).to eq(disparo.id)
        expect(snapshot.total_eligible).to eq(1)
        expect(snapshot.by_skip_reason).to eq('opt_out_lgpd' => 1)
        expect(snapshot.by_inbox).to eq(cloud_inbox.id.to_s => 1)
        expect(snapshot.inbox_ids).to eq([cloud_inbox.id])
        expect(snapshot.filter_dsl).to eq(filter)
        expect(snapshot.expires_at).to eq(now + 15.minutes)
      end
    end

    context 'with run-level observability (US20: ids + counts only, no PII)', :aggregate_failures do
      it 'emits dry_run_started + dry_run_completed with safe payload keys (no phone/hmac/token)' do
        candidate(contact: create(:contact, account: account, phone_number: '+5511999998888'))
        opted_out = create(:contact, account: account, phone_number: '+5511988887777')
        candidate(contact: opted_out, custom_attributes: { 'opt_out_lgpd' => true })

        captured = []
        ActiveSupport::Notifications.subscribed(
          ->(name, _start, _finish, _id, payload) { captured << [name, payload] }, /\Adisparos\.dry_run_/
        ) { service.perform(disparo) }

        names = captured.map(&:first)
        expect(names).to eq(%w[disparos.dry_run_started disparos.dry_run_completed])

        started_payload = captured.find { |name, _| name == 'disparos.dry_run_started' }.last
        completed_payload = captured.find { |name, _| name == 'disparos.dry_run_completed' }.last

        expect(started_payload.keys).to contain_exactly(:disparo_id)
        expect(started_payload[:disparo_id]).to eq(disparo.id)

        # Exact key set proves the safe keys AND that no phone/phone_number/hmac/token rode along.
        expect(completed_payload.keys).to contain_exactly(:disparo_id, :total_eligible, :total_skipped)
        expect(completed_payload[:total_eligible]).to eq(1)
        expect(completed_payload[:total_skipped]).to eq(1)
      end
    end

    context 'with the read-only / shadow guarantee (AC5/AC6)' do
      it 'never creates a Message, Conversation or DisparoTarget' do
        candidate(contact: create(:contact, account: account, phone_number: '+5511999998888'))
        opted_out = create(:contact, account: account, phone_number: '+5511988887777')
        candidate(contact: opted_out, custom_attributes: { 'opt_out_lgpd' => true })

        expect { service.perform(disparo) }
          .to not_change(Message, :count)
          .and not_change(Conversation, :count)
          .and not_change(DisparoTarget, :count)

        expect(DisparoTarget.count).to eq(0)
      end
    end
  end
end
