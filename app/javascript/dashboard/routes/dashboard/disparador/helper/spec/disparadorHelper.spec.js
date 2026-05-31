import {
  statusLabelKey,
  skipReasonLabelKey,
  skipReasonRows,
  hasKnownCost,
  formatCostCents,
  resolveDisparadorSettings,
  DISPARADOR_SETTINGS_DEFAULTS,
  mapTemplateCategory,
  templateCategoryLabelKey,
} from '../disparadorHelper';

describe('disparadorHelper', () => {
  // GAP A: this mapping MUST mirror app/services/disparos/template_category.rb
  // exactly, or the FE will allow a payload the backend 422s (or block one it
  // would accept).
  describe('#mapTemplateCategory', () => {
    it('maps MARKETING -> marketing (case-insensitive)', () => {
      expect(mapTemplateCategory('MARKETING')).toBe('marketing');
      expect(mapTemplateCategory('marketing')).toBe('marketing');
    });

    it('maps AUTHENTICATION -> authentication', () => {
      expect(mapTemplateCategory('AUTHENTICATION')).toBe('authentication');
    });

    it('maps UTILITY and legacy values -> utility', () => {
      expect(mapTemplateCategory('UTILITY')).toBe('utility');
      expect(mapTemplateCategory('SHIPPING_UPDATE')).toBe('utility');
      expect(mapTemplateCategory('ACCOUNT_UPDATE')).toBe('utility');
      expect(mapTemplateCategory('TICKET_UPDATE')).toBe('utility');
    });

    it('returns null for an absent/blank category (uncreatable, not utility)', () => {
      expect(mapTemplateCategory(null)).toBeNull();
      expect(mapTemplateCategory(undefined)).toBeNull();
      expect(mapTemplateCategory('')).toBeNull();
    });
  });

  describe('#templateCategoryLabelKey', () => {
    it('maps each enum category to its i18n key', () => {
      expect(templateCategoryLabelKey('marketing')).toBe(
        'DISPARADOR_MGMT.CREATE.FORM.CATEGORY.MARKETING'
      );
      expect(templateCategoryLabelKey('utility')).toBe(
        'DISPARADOR_MGMT.CREATE.FORM.CATEGORY.UTILITY'
      );
      expect(templateCategoryLabelKey('authentication')).toBe(
        'DISPARADOR_MGMT.CREATE.FORM.CATEGORY.AUTHENTICATION'
      );
    });

    it('returns null for null/unknown so no badge is rendered', () => {
      expect(templateCategoryLabelKey(null)).toBeNull();
      expect(templateCategoryLabelKey(undefined)).toBeNull();
    });
  });

  describe('#statusLabelKey', () => {
    it('maps known statuses to i18n keys', () => {
      expect(statusLabelKey('draft')).toBe('DISPARADOR_MGMT.STATUS.DRAFT');
      expect(statusLabelKey('completed')).toBe(
        'DISPARADOR_MGMT.STATUS.COMPLETED'
      );
    });

    it('returns null for unknown statuses so caller falls back to raw value', () => {
      expect(statusLabelKey('unknown_status')).toBeNull();
    });
  });

  describe('#skipReasonLabelKey', () => {
    // The FULL set of skip reasons, mirroring
    // Disparos::EligibilityEngine::PRECEDENCE (13 reasons). Each is pinned to its
    // EXACT i18n key so a re-omission (e.g. inbox_not_approved was missing) or a
    // wrong-key mapping is caught, not just a loose "starts with the namespace".
    const SKIP_REASON_EXPECTATIONS = {
      unsupported_inbox_provider:
        'DISPARADOR_MGMT.DRY_RUN.SKIP_REASONS.UNSUPPORTED_INBOX_PROVIDER',
      inbox_not_approved:
        'DISPARADOR_MGMT.DRY_RUN.SKIP_REASONS.INBOX_NOT_APPROVED',
      missing_phone: 'DISPARADOR_MGMT.DRY_RUN.SKIP_REASONS.MISSING_PHONE',
      invalid_phone: 'DISPARADOR_MGMT.DRY_RUN.SKIP_REASONS.INVALID_PHONE',
      label_agente_off_permanente:
        'DISPARADOR_MGMT.DRY_RUN.SKIP_REASONS.LABEL_AGENTE_OFF_PERMANENTE',
      opt_out_lgpd: 'DISPARADOR_MGMT.DRY_RUN.SKIP_REASONS.OPT_OUT_LGPD',
      stage_opt_out: 'DISPARADOR_MGMT.DRY_RUN.SKIP_REASONS.STAGE_OPT_OUT',
      followup_locked: 'DISPARADOR_MGMT.DRY_RUN.SKIP_REASONS.FOLLOWUP_LOCKED',
      invalid_window_closes_at:
        'DISPARADOR_MGMT.DRY_RUN.SKIP_REASONS.INVALID_WINDOW_CLOSES_AT',
      window_incompatible:
        'DISPARADOR_MGMT.DRY_RUN.SKIP_REASONS.WINDOW_INCOMPATIBLE',
      template_sent_last_7d:
        'DISPARADOR_MGMT.DRY_RUN.SKIP_REASONS.TEMPLATE_SENT_LAST_7D',
      marketing_cooldown_7d:
        'DISPARADOR_MGMT.DRY_RUN.SKIP_REASONS.MARKETING_COOLDOWN_7D',
      whatsapp_invalid_30d:
        'DISPARADOR_MGMT.DRY_RUN.SKIP_REASONS.WHATSAPP_INVALID_30D',
    };

    it('maps every eligibility skip reason to its exact i18n key', () => {
      // Guards against drift: the count must equal the backend PRECEDENCE size.
      expect(Object.keys(SKIP_REASON_EXPECTATIONS)).toHaveLength(13);
      Object.entries(SKIP_REASON_EXPECTATIONS).forEach(([reason, key]) => {
        expect(skipReasonLabelKey(reason)).toBe(key);
      });
    });

    it('returns null for an unknown reason key', () => {
      expect(skipReasonLabelKey('some_future_reason')).toBeNull();
    });
  });

  describe('#skipReasonRows', () => {
    it('returns rows sorted by count descending', () => {
      const rows = skipReasonRows({
        missing_phone: 3,
        opt_out_lgpd: 7,
        invalid_phone: 1,
      });
      expect(rows).toEqual([
        { reason: 'opt_out_lgpd', count: 7 },
        { reason: 'missing_phone', count: 3 },
        { reason: 'invalid_phone', count: 1 },
      ]);
    });

    it('handles an empty/undefined map', () => {
      expect(skipReasonRows()).toEqual([]);
      expect(skipReasonRows({})).toEqual([]);
    });
  });

  describe('#hasKnownCost', () => {
    it('treats null/undefined as unknown price', () => {
      expect(hasKnownCost(null)).toBe(false);
      expect(hasKnownCost(undefined)).toBe(false);
    });

    it('treats an integer (including 0) as a known price', () => {
      expect(hasKnownCost(0)).toBe(true);
      expect(hasKnownCost(1500)).toBe(true);
    });
  });

  describe('#formatCostCents', () => {
    it('formats cents into a dollar string', () => {
      expect(formatCostCents(1500)).toBe('$15.00');
      expect(formatCostCents(0)).toBe('$0.00');
    });
  });

  describe('#resolveDisparadorSettings', () => {
    // The defaults MUST mirror app/services/disparos/rules_config.rb so the UI
    // shows the operator the value the engine actually uses when a key is unset.
    it('exposes the engine defaults verbatim', () => {
      expect(DISPARADOR_SETTINGS_DEFAULTS).toEqual({
        opt_out_label: 'agente-off-permanente',
        kanban_opt_out_steps: ['9'],
        opt_out_lgpd_key: 'opt_out_lgpd',
        followup_locked_key: 'followup_locked',
        window_closes_at_key: 'window_closes_at',
        kanban_step_key: 'kanban_step',
        whatsapp_invalid_at_key: 'whatsapp_invalid_at',
        dedup_window_days: 7,
        whatsapp_invalid_window_days: 30,
      });
    });

    it('returns the full defaults for a nil/empty stored hash', () => {
      expect(resolveDisparadorSettings()).toEqual(DISPARADOR_SETTINGS_DEFAULTS);
      expect(resolveDisparadorSettings(null)).toEqual(
        DISPARADOR_SETTINGS_DEFAULTS
      );
      expect(resolveDisparadorSettings({})).toEqual(
        DISPARADOR_SETTINGS_DEFAULTS
      );
    });

    it('keeps explicit overrides and coerces step values to strings', () => {
      const resolved = resolveDisparadorSettings({
        opt_out_label: 'no-contact',
        kanban_opt_out_steps: [9, '12'],
        dedup_window_days: 5,
        whatsapp_invalid_window_days: 45,
      });
      expect(resolved.opt_out_label).toBe('no-contact');
      expect(resolved.kanban_opt_out_steps).toEqual(['9', '12']);
      expect(resolved.dedup_window_days).toBe(5);
      expect(resolved.whatsapp_invalid_window_days).toBe(45);
    });

    it('falls back to defaults for blank strings, blank arrays and non-positive windows', () => {
      const resolved = resolveDisparadorSettings({
        opt_out_label: '   ',
        kanban_opt_out_steps: [],
        dedup_window_days: 0,
        whatsapp_invalid_window_days: -3,
      });
      expect(resolved.opt_out_label).toBe(
        DISPARADOR_SETTINGS_DEFAULTS.opt_out_label
      );
      expect(resolved.kanban_opt_out_steps).toEqual(['9']);
      expect(resolved.dedup_window_days).toBe(7);
      expect(resolved.whatsapp_invalid_window_days).toBe(30);
    });
  });
});
