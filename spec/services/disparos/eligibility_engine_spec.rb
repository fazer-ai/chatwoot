require 'rails_helper'

describe Disparos::EligibilityEngine do
  subject(:result) { described_class.new(conversation: conversation, template_name: template_name, now: now).perform }

  let(:account) { create(:account) }
  let(:cloud_channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', sync_templates: false, validate_provider_config: false)
  end
  let(:cloud_inbox) { cloud_channel.inbox }
  let(:contact) { create(:contact, account: account, phone_number: '+5511999998888') }
  # The factory's default message_templates approve this name (status 'approved'),
  # so the default cloud inbox is on the per-template allowlist (G4).
  let(:template_name) { 'sample_shipping_confirmation' }
  let(:now) { Time.zone.parse('2026-05-29 12:00:00') }

  def build_conversation(custom_attributes: {}, label_list: nil, contact: nil, inbox: cloud_inbox)
    attrs = { account: account, inbox: inbox, custom_attributes: custom_attributes }
    attrs[:contact] = contact if contact
    attrs[:label_list] = label_list if label_list
    create(:conversation, **attrs)
  end

  describe '#perform' do
    context 'with a normal qualified candidate' do
      let(:conversation) { build_conversation(contact: contact) }

      it 'is eligible with no skip reasons and a nil primary reason' do
        expect(result).to be_eligible
        expect(result.skip_reasons).to be_empty
        expect(result.primary_skip_reason).to be_nil
      end
    end

    context 'when the contact has no phone (missing_phone)' do
      let(:no_phone_contact) { create(:contact, account: account, phone_number: nil) }
      let(:conversation) { build_conversation(contact: no_phone_contact) }

      it 'skips with missing_phone and never also adds invalid_phone' do
        expect(result).not_to be_eligible
        expect(result.skip_reasons).to contain_exactly('missing_phone')
        expect(result.primary_skip_reason).to eq('missing_phone')
      end
    end

    context 'when the phone is present but not E.164 (invalid_phone)' do
      let(:bad_phone_contact) { build(:contact, account: account, phone_number: '12345') }
      let(:conversation) do
        bad_phone_contact.save!(validate: false)
        build_conversation(contact: bad_phone_contact)
      end

      it 'skips with invalid_phone' do
        expect(result).not_to be_eligible
        expect(result.skip_reasons).to contain_exactly('invalid_phone')
        expect(result.primary_skip_reason).to eq('invalid_phone')
      end
    end

    context 'when opt_out_lgpd is truthy (AC14)' do
      let(:conversation) { build_conversation(contact: contact, custom_attributes: { 'opt_out_lgpd' => true }) }

      it 'is never eligible' do
        expect(result).not_to be_eligible
        expect(result.skip_reasons).to include('opt_out_lgpd')
        expect(result.primary_skip_reason).to eq('opt_out_lgpd')
      end
    end

    context 'when carrying the agente-off-permanente label (AC15)' do
      let(:conversation) { build_conversation(contact: contact, label_list: ['agente-off-permanente']) }

      it 'is never eligible' do
        expect(result).not_to be_eligible
        expect(result.skip_reasons).to include('label_agente_off_permanente')
        expect(result.primary_skip_reason).to eq('label_agente_off_permanente')
      end

      # The cached label list is NOT downcased, but AudienceResolver pulls labels
      # case-insensitively (tagged_with), so a mixed-case opt-out label must still
      # trip the gate — otherwise it would be pulled into the audience yet wrongly
      # pass eligibility.
      it 'matches a mixed-case opt-out label case-insensitively' do
        mixed = build_conversation(contact: contact, label_list: ['Agente-Off-Permanente'])
        res = described_class.new(conversation: mixed, template_name: template_name, now: now).perform

        expect(res).not_to be_eligible
        expect(res.skip_reasons).to include('label_agente_off_permanente')
        expect(res.primary_skip_reason).to eq('label_agente_off_permanente')
      end
    end

    context 'when kanban_step is Stage-9 (AC16)' do
      let(:conversation) { build_conversation(contact: contact, custom_attributes: { 'kanban_step' => '9' }) }

      it 'is never eligible' do
        expect(result).not_to be_eligible
        expect(result.skip_reasons).to include('stage_opt_out')
        expect(result.primary_skip_reason).to eq('stage_opt_out')
      end

      it 'matches a numeric Stage-9 value as a string (jsonb text trap)' do
        numeric = build_conversation(contact: contact, custom_attributes: { 'kanban_step' => 9 })
        engine = described_class.new(conversation: numeric, template_name: template_name, now: now)

        expect(engine.perform.skip_reasons).to include('stage_opt_out')
      end
    end

    context 'when followup_locked is true (AC22)' do
      let(:conversation) { build_conversation(contact: contact, custom_attributes: { 'followup_locked' => true }) }

      it 'skips with followup_locked' do
        expect(result).not_to be_eligible
        expect(result.skip_reasons).to include('followup_locked')
        expect(result.primary_skip_reason).to eq('followup_locked')
      end
    end

    context 'with the WhatsApp free-form window' do
      it 'skips with window_incompatible when window_closes_at > now (AC17)' do
        conversation = build_conversation(contact: contact, custom_attributes: { 'window_closes_at' => (now + 1.hour).iso8601 })
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).not_to be_eligible
        expect(res.skip_reasons).to contain_exactly('window_incompatible')
        expect(res.primary_skip_reason).to eq('window_incompatible')
      end

      it 'is eligible re: window when window_closes_at <= now (AC18)' do
        conversation = build_conversation(contact: contact, custom_attributes: { 'window_closes_at' => (now - 1.hour).iso8601 })
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).to be_eligible
        expect(res.skip_reasons).to be_empty
      end

      it 'is eligible when window_closes_at is empty per the frozen contract (AC19)' do
        conversation = build_conversation(contact: contact, custom_attributes: { 'window_closes_at' => '' })
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).to be_eligible
        expect(res.skip_reasons).to be_empty
      end

      it 'skips with invalid_window_closes_at when window_closes_at is unparseable (AC20)' do
        conversation = build_conversation(contact: contact, custom_attributes: { 'window_closes_at' => 'not-a-date' })
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).not_to be_eligible
        expect(res.skip_reasons).to contain_exactly('invalid_window_closes_at')
        expect(res.primary_skip_reason).to eq('invalid_window_closes_at')
      end

      it 'skips with invalid_window_closes_at for digit-garbage that lenient parsing would coerce' do
        conversation = build_conversation(contact: contact, custom_attributes: { 'window_closes_at' => 'garbage123' })
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).not_to be_eligible
        expect(res.skip_reasons).to contain_exactly('invalid_window_closes_at')
        expect(res.primary_skip_reason).to eq('invalid_window_closes_at')
      end
    end

    context 'with legacy 7-day dedup (AC21)' do
      it 'skips with template_sent_last_7d when the template was sent 3 days ago (inside window)' do
        conversation = build_conversation(contact: contact, custom_attributes: { "bulk_template_#{template_name}_sent_at" => (now - 3.days).iso8601 })
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).not_to be_eligible
        expect(res.skip_reasons).to contain_exactly('template_sent_last_7d')
        expect(res.primary_skip_reason).to eq('template_sent_last_7d')
      end

      it 'is eligible when the template was sent 10 days ago (outside the 7-day window)' do
        attrs = { "bulk_template_#{template_name}_sent_at" => (now - 10.days).iso8601 }
        conversation = build_conversation(contact: contact, custom_attributes: attrs)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).to be_eligible
        expect(res.skip_reasons).to be_empty
      end

      it 'is eligible at the exact 7-day boundary (sent-at == now - 7.days; the cutoff is strictly >)' do
        attrs = { "bulk_template_#{template_name}_sent_at" => (now - 7.days).iso8601 }
        conversation = build_conversation(contact: contact, custom_attributes: attrs)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).to be_eligible
        expect(res.skip_reasons).to be_empty
      end

      it 'does not fabricate template_sent_last_7d from a digit-garbage sent-at value' do
        attrs = { "bulk_template_#{template_name}_sent_at" => 'garbage123' }
        conversation = build_conversation(contact: contact, custom_attributes: attrs)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).to be_eligible
        expect(res.skip_reasons).not_to include('template_sent_last_7d')
      end

      it 'is scoped per template name (a different template does not trigger the skip)' do
        conversation = build_conversation(contact: contact, custom_attributes: { 'bulk_template_other_promo_sent_at' => (now - 1.day).iso8601 })
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).to be_eligible
      end
    end

    context 'with contact-mirror dedup (W2)' do
      it 'skips template_sent_last_7d when the marker lives ONLY on the contact within 7d' do
        mirror_contact = create(:contact, account: account, phone_number: '+5511999990000',
                                          custom_attributes: { "bulk_template_#{template_name}_sent_at" => (now - 2.days).iso8601 })
        conversation = build_conversation(contact: mirror_contact)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).not_to be_eligible
        expect(res.skip_reasons).to contain_exactly('template_sent_last_7d')
        expect(res.primary_skip_reason).to eq('template_sent_last_7d')
      end
    end

    # GAP E: the marketing cooldown is now scoped to markers whose OWN template
    # resolves to a MARKETING-category approved template on the inbox's channel
    # (via Disparos::TemplateCategory). A recent marker keyed to a KNOWN marketing
    # template trips it; a UTILITY-template or UNKNOWN-template marker does NOT
    # (the safe direction — do not over-block on a template we cannot prove was
    # marketing). The cooldown inbox below approves both the disparo template
    # (sample_shipping_confirmation, legacy SHIPPING_UPDATE -> utility) and the
    # markers' templates so resolution is exercised end-to-end.
    context 'with the MARKETING cross-template cooldown (W2 / GAP E category-scoped)' do
      let(:cooldown_inbox) do
        create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                  sync_templates: false, validate_provider_config: false,
                                  message_templates: [
                                    { 'name' => template_name, 'status' => 'approved', 'category' => 'SHIPPING_UPDATE' },
                                    { 'name' => 'promo_blast', 'status' => 'approved', 'category' => 'MARKETING' },
                                    { 'name' => 'utility_receipt', 'status' => 'approved', 'category' => 'UTILITY' }
                                  ]).inbox
      end
      let(:marketing_marker) { { 'bulk_template_promo_blast_sent_at' => (now - 1.day).iso8601 } }

      it 'skips marketing_cooldown_7d for a marketing template with a recent KNOWN-MARKETING-template marker' do
        conversation = build_conversation(contact: contact, inbox: cooldown_inbox, custom_attributes: marketing_marker)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now, template_category: :marketing).perform

        expect(res).not_to be_eligible
        expect(res.skip_reasons).to contain_exactly('marketing_cooldown_7d')
        expect(res.primary_skip_reason).to eq('marketing_cooldown_7d')
      end

      it 'is eligible for a utility template with the SAME recent marketing marker (cooldown is marketing-only)' do
        conversation = build_conversation(contact: contact, inbox: cooldown_inbox, custom_attributes: marketing_marker)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now, template_category: :utility).perform

        expect(res).to be_eligible
        expect(res.skip_reasons).to be_empty
      end

      it 'reads the marketing cooldown marker from the contact mirror as well' do
        cooldown_contact = create(:contact, account: account, phone_number: '+5511999991111',
                                            custom_attributes: { 'bulk_template_promo_blast_sent_at' => (now - 1.day).iso8601 })
        conversation = build_conversation(contact: cooldown_contact, inbox: cooldown_inbox)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now, template_category: :marketing).perform

        expect(res.skip_reasons).to include('marketing_cooldown_7d')
      end

      # COOLDOWN MUST NOT FAIL OPEN ON A MIXED-CASE HISTORICAL MARKER (Codex regression).
      # The synced template is `promo_blast` (MARKETING) but a historical /
      # externally-written marker can carry a differently-cased name
      # (`bulk_template_PROMO_BLAST_sent_at`) that never passed the create-time
      # exact-case guard. marker_category resolves with the GENEROUS (default,
      # case-insensitive) classifier, so it STILL maps to MARKETING and the cooldown
      # trips. If the resolver default were exact (case-sensitive), this marker would
      # resolve to nil and the cooldown would fail open — the lead would be eligible.
      it 'trips marketing_cooldown_7d for a recent MIXED-CASE marketing marker (cooldown does not fail open)' do
        mixed_case_marker = { 'bulk_template_PROMO_BLAST_sent_at' => (now - 1.day).iso8601 }
        conversation = build_conversation(contact: contact, inbox: cooldown_inbox, custom_attributes: mixed_case_marker)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now, template_category: :marketing).perform

        expect(res).not_to be_eligible
        expect(res.skip_reasons).to contain_exactly('marketing_cooldown_7d')
        expect(res.primary_skip_reason).to eq('marketing_cooldown_7d')
      end

      it 'does NOT trip marketing_cooldown_7d from a recent KNOWN-UTILITY-template marker (GAP E narrowed)' do
        utility_marker = { 'bulk_template_utility_receipt_sent_at' => (now - 1.day).iso8601 }
        conversation = build_conversation(contact: contact, inbox: cooldown_inbox, custom_attributes: utility_marker)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now, template_category: :marketing).perform

        expect(res).to be_eligible
        expect(res.skip_reasons).not_to include('marketing_cooldown_7d')
      end

      # SAFE DIRECTION (documented in the engine): a marker whose template is NOT
      # in the channel's message_templates is UNKNOWN — we cannot prove it was
      # marketing, so it must NOT suppress a send.
      it 'does NOT trip marketing_cooldown_7d from a recent UNKNOWN-template marker (safe direction)' do
        unknown_marker = { 'bulk_template_other_promo_sent_at' => (now - 1.day).iso8601 }
        conversation = build_conversation(contact: contact, inbox: cooldown_inbox, custom_attributes: unknown_marker)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now, template_category: :marketing).perform

        expect(res).to be_eligible
        expect(res.skip_reasons).not_to include('marketing_cooldown_7d')
      end
    end

    context 'with the whatsapp_invalid_30d contact rule (W2)' do
      it 'skips whatsapp_invalid_30d when the contact was flagged within 30d' do
        invalid_contact = create(:contact, account: account, phone_number: '+5511999992222',
                                           custom_attributes: { 'whatsapp_invalid_at' => (now - 10.days).iso8601 })
        conversation = build_conversation(contact: invalid_contact)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).not_to be_eligible
        expect(res.skip_reasons).to contain_exactly('whatsapp_invalid_30d')
        expect(res.primary_skip_reason).to eq('whatsapp_invalid_30d')
      end

      it 'is eligible when the contact was flagged more than 30d ago' do
        old_invalid_contact = create(:contact, account: account, phone_number: '+5511999993333',
                                               custom_attributes: { 'whatsapp_invalid_at' => (now - 40.days).iso8601 })
        conversation = build_conversation(contact: old_invalid_contact)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).to be_eligible
        expect(res.skip_reasons).to be_empty
      end
    end

    # R1a — the strictness_mode toggle is removed: followup_locked is now an
    # always-applied opt-out (it used to be gated to `padrao`). There is no mode
    # param; followup_locked fires unconditionally alongside every other skip.
    context 'when followup_locked is set, it is ALWAYS applied (no strictness gate)' do
      let(:locked_attrs) { { 'followup_locked' => true } }

      it 'skips followup_locked with no mode param' do
        conversation = build_conversation(contact: contact, custom_attributes: locked_attrs)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).not_to be_eligible
        expect(res.skip_reasons).to contain_exactly('followup_locked')
        expect(res.primary_skip_reason).to eq('followup_locked')
      end

      it 'still fires alongside other skips (it is not relaxed by any toggle)', :aggregate_failures do
        conversation = build_conversation(
          contact: contact,
          custom_attributes: { 'followup_locked' => true, 'opt_out_lgpd' => true, 'window_closes_at' => (now + 2.days).iso8601 }
        )
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).not_to be_eligible
        expect(res.skip_reasons).to contain_exactly('followup_locked', 'opt_out_lgpd', 'window_incompatible')
      end
    end

    context 'with the reconciled precedence (W2)' do
      # The default cloud_inbox approves sample_shipping_confirmation (legacy
      # SHIPPING_UPDATE -> utility). The per-template marker trips
      # template_sent_last_7d; the cross-template `other_promo` marker is an
      # UNKNOWN template (not in the channel) so under GAP E it does NOT trip the
      # marketing cooldown. marketing_cooldown_7d therefore drops out.
      it 'picks label_agente_off_permanente over opt_out_lgpd and collects every reason' do
        conversation = build_conversation(
          contact: contact,
          label_list: ['agente-off-permanente'],
          custom_attributes: {
            'opt_out_lgpd' => true,
            "bulk_template_#{template_name}_sent_at" => (now - 1.day).iso8601,
            'bulk_template_other_promo_sent_at' => (now - 1.day).iso8601
          }
        )
        res = described_class.new(conversation: conversation, template_name: template_name, now: now, template_category: :marketing).perform

        expect(res.primary_skip_reason).to eq('label_agente_off_permanente')
        expect(res.skip_reasons).to contain_exactly(
          'label_agente_off_permanente', 'opt_out_lgpd', 'template_sent_last_7d'
        )
      end
    end

    context 'when the inbox provider is not WhatsApp Cloud' do
      it 'skips with unsupported_inbox_provider for a baileys inbox' do
        baileys_channel = create(:channel_whatsapp, account: account, provider: 'baileys', sync_templates: false, validate_provider_config: false)
        conversation = build_conversation(contact: contact, inbox: baileys_channel.inbox)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).not_to be_eligible
        expect(res.skip_reasons).to contain_exactly('unsupported_inbox_provider')
        expect(res.primary_skip_reason).to eq('unsupported_inbox_provider')
      end

      it 'skips with unsupported_inbox_provider for the default (360dialog) provider, which is NOT Cloud' do
        default_channel = create(:channel_whatsapp, account: account, provider: 'default', sync_templates: false, validate_provider_config: false)
        conversation = build_conversation(contact: contact, inbox: default_channel.inbox)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).not_to be_eligible
        expect(res.skip_reasons).to contain_exactly('unsupported_inbox_provider')
      end

      it 'skips with unsupported_inbox_provider for a non-whatsapp (web widget) inbox' do
        widget_inbox = create(:inbox, account: account)
        conversation = build_conversation(contact: contact, inbox: widget_inbox)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res.skip_reasons).to include('unsupported_inbox_provider')
      end

      it 'never also adds inbox_not_approved for a non-cloud inbox (no double-stack with the provider gate)' do
        baileys_channel = create(:channel_whatsapp, account: account, provider: 'baileys', sync_templates: false, validate_provider_config: false)
        conversation = build_conversation(contact: contact, inbox: baileys_channel.inbox)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res.skip_reasons).to include('unsupported_inbox_provider')
        expect(res.skip_reasons).not_to include('inbox_not_approved')
      end
    end

    context 'with the approved-inbox allowlist (W1/§4.2, G4)' do
      # A cloud inbox whose synced templates do NOT carry the disparo's template_name.
      let(:unapproved_inbox) do
        create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                  sync_templates: false, validate_provider_config: false,
                                  message_templates: []).inbox
      end

      it 'skips inbox_not_approved when the cloud inbox has no approved entry for the template' do
        conversation = build_conversation(contact: contact, inbox: unapproved_inbox)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).not_to be_eligible
        expect(res.skip_reasons).to contain_exactly('inbox_not_approved')
        expect(res.primary_skip_reason).to eq('inbox_not_approved')
      end

      it 'is eligible (no inbox_not_approved) when the cloud inbox approves the template' do
        # The default cloud_inbox's factory templates approve `sample_shipping_confirmation`.
        conversation = build_conversation(contact: contact)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).to be_eligible
        expect(res.skip_reasons).to be_empty
      end

      it 'matches an approved entry case-insensitively (status "APPROVED" counts)' do
        upper_inbox = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                                sync_templates: false, validate_provider_config: false,
                                                message_templates: [{ 'name' => template_name, 'status' => 'APPROVED' }]).inbox
        conversation = build_conversation(contact: contact, inbox: upper_inbox)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).to be_eligible
        expect(res.skip_reasons).to be_empty
      end

      it 'is inbox_not_approved when the only matching entry is not approved (pending/rejected)' do
        pending_inbox = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                                  sync_templates: false, validate_provider_config: false,
                                                  message_templates: [{ 'name' => template_name, 'status' => 'PENDING' }]).inbox
        conversation = build_conversation(contact: contact, inbox: pending_inbox)
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res.skip_reasons).to contain_exactly('inbox_not_approved')
      end
    end

    context 'when multiple rules fail simultaneously (AC34, AC35, AC44)' do
      it 'collects opt_out AND dedup, with opt_out_lgpd as primary by precedence' do
        conversation = build_conversation(
          contact: contact,
          custom_attributes: {
            'opt_out_lgpd' => true,
            "bulk_template_#{template_name}_sent_at" => (now - 2.days).iso8601
          }
        )
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).not_to be_eligible
        expect(res.skip_reasons).to contain_exactly('opt_out_lgpd', 'template_sent_last_7d')
        expect(res.primary_skip_reason).to eq('opt_out_lgpd')
      end

      it 'collects invalid_phone AND stage_opt_out, with invalid_phone as primary (AC44)' do
        bad_phone_contact = build(:contact, account: account, phone_number: '12345')
        bad_phone_contact.save!(validate: false)
        conversation = build_conversation(contact: bad_phone_contact, custom_attributes: { 'kanban_step' => '9' })
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).not_to be_eligible
        expect(res.skip_reasons).to contain_exactly('invalid_phone', 'stage_opt_out')
        expect(res.primary_skip_reason).to eq('invalid_phone')
      end

      it 'collects invalid_phone AND opt_out_lgpd, with invalid_phone as primary (AC44 opt-out + invalid-phone)' do
        bad_phone_contact = build(:contact, account: account, phone_number: '12345')
        bad_phone_contact.save!(validate: false)
        conversation = build_conversation(contact: bad_phone_contact, custom_attributes: { 'opt_out_lgpd' => true })
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res).not_to be_eligible
        expect(res.skip_reasons).to contain_exactly('invalid_phone', 'opt_out_lgpd')
        expect(res.primary_skip_reason).to eq('invalid_phone')
      end

      it 'keeps opt_out_lgpd in skip_reasons even when a higher-precedence phone reason is primary (AC44 compliance breakdown)' do
        no_phone_contact = create(:contact, account: account, phone_number: nil)
        conversation = build_conversation(contact: no_phone_contact, custom_attributes: { 'opt_out_lgpd' => true })
        res = described_class.new(conversation: conversation, template_name: template_name, now: now).perform

        expect(res.skip_reasons).to contain_exactly('missing_phone', 'opt_out_lgpd')
        expect(res.primary_skip_reason).to eq('missing_phone')
      end
    end

    context 'with the result value object (AC34)' do
      let(:conversation) { build_conversation(contact: contact, custom_attributes: { 'opt_out_lgpd' => true }) }

      it 'exposes skip_reasons, primary_skip_reason and eligible?' do
        expect(result).to respond_to(:skip_reasons, :primary_skip_reason, :eligible?)
        expect(result.skip_reasons).to be_an(Array)
      end
    end

    # R1b — the rule BINDINGS (opt-out label, opt-out kanban stages, attr keys,
    # windows) are now resolved per-account via an injected Disparos::RulesConfig.
    # The DEFAULT config (no config: argument, or an account with no settings)
    # reproduces today's behavior EXACTLY — that is the surviving-spec anchor
    # above. These specs prove a CUSTOM config is honored and the default still
    # uses the original bindings.
    context 'with a per-account custom RulesConfig (R1b)' do
      it 'honors a CUSTOM opt-out label (the custom label is skipped; the default label is NOT)', :aggregate_failures do
        custom_account = create(:account)
        custom_account.update!(disparador_settings: { 'opt_out_label' => 'no-contact' })
        config = Disparos::RulesConfig.new(custom_account)

        custom_labeled = build_conversation(contact: contact, label_list: ['No-Contact'])
        res = described_class.new(conversation: custom_labeled, template_name: template_name, now: now, config: config).perform
        expect(res.skip_reasons).to include('label_agente_off_permanente')

        # The default opt-out label no longer trips this account's gate.
        default_labeled = build_conversation(contact: contact, label_list: ['agente-off-permanente'])
        res2 = described_class.new(conversation: default_labeled, template_name: template_name, now: now, config: config).perform
        expect(res2.skip_reasons).not_to include('label_agente_off_permanente')
      end

      it 'honors a CUSTOM kanban_opt_out_steps array (default Stage-9 no longer opts out)', :aggregate_failures do
        config = Disparos::RulesConfig.new(build_account_with(kanban_opt_out_steps: %w[7 8]))

        stage7 = build_conversation(contact: contact, custom_attributes: { 'kanban_step' => '7' })
        expect(eligible_skips(stage7, config)).to include('stage_opt_out')

        stage9 = build_conversation(contact: contact, custom_attributes: { 'kanban_step' => '9' })
        expect(eligible_skips(stage9, config)).not_to include('stage_opt_out')
      end

      it 'honors a CUSTOM custom-attribute key (e.g. opt_out_lgpd_key)', :aggregate_failures do
        config = Disparos::RulesConfig.new(build_account_with(opt_out_lgpd_key: 'gdpr_opt_out'))

        custom_key = build_conversation(contact: contact, custom_attributes: { 'gdpr_opt_out' => true })
        expect(eligible_skips(custom_key, config)).to include('opt_out_lgpd')

        default_key = build_conversation(contact: contact, custom_attributes: { 'opt_out_lgpd' => true })
        expect(eligible_skips(default_key, config)).not_to include('opt_out_lgpd')
      end

      it 'honors a CUSTOM dedup window (a 10-day-old marker trips a 14-day window)' do
        config = Disparos::RulesConfig.new(build_account_with(dedup_window_days: 14))
        attrs = { "bulk_template_#{template_name}_sent_at" => (now - 10.days).iso8601 }
        conversation = build_conversation(contact: contact, custom_attributes: attrs)

        res = described_class.new(conversation: conversation, template_name: template_name, now: now, config: config).perform
        expect(res.skip_reasons).to contain_exactly('template_sent_last_7d')
      end

      it 'with NO config set, applies the original DEFAULT bindings (Stage-9 + default label + default 7-day window)', :aggregate_failures do
        no_settings_account = create(:account)
        config = Disparos::RulesConfig.new(no_settings_account)

        stage9 = build_conversation(contact: contact, custom_attributes: { 'kanban_step' => '9' })
        expect(eligible_skips(stage9, config)).to include('stage_opt_out')

        default_labeled = build_conversation(contact: contact, label_list: ['agente-off-permanente'])
        expect(eligible_skips(default_labeled, config)).to include('label_agente_off_permanente')

        # A 10-day-old marker is OUTSIDE the default 7-day window.
        old_marker = build_conversation(contact: contact,
                                        custom_attributes: { "bulk_template_#{template_name}_sent_at" => (now - 10.days).iso8601 })
        expect(eligible_skips(old_marker, config)).not_to include('template_sent_last_7d')
      end
    end
  end

  def build_account_with(overrides)
    account = create(:account)
    account.update!(disparador_settings: overrides.stringify_keys)
    account
  end

  def eligible_skips(conversation, config)
    described_class.new(conversation: conversation, template_name: template_name, now: now, config: config).perform.skip_reasons
  end
end
