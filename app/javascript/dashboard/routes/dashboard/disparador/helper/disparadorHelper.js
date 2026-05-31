// Presentation helpers for the Disparador (Beta 0) settings page. They map raw
// API keys (status enum, skip-reason keys) to i18n keys so the UI never renders
// raw machine values, and they keep that mapping testable in isolation.

// Maps a raw Meta template category to the Disparo `template_category` enum,
// MIRRORING app/services/disparos/template_category.rb#map_category exactly:
//   'MARKETING'      -> 'marketing'
//   'AUTHENTICATION' -> 'authentication'
//   EVERYTHING ELSE  -> 'utility' (covers 'UTILITY' AND legacy values such as
//                                  'SHIPPING_UPDATE' / 'ACCOUNT_UPDATE')
// A blank/absent raw category returns null — the backend's resolver treats a
// template with no category as a mismatch (422), so the FE must too: null means
// "uncreatable, block the operator", NOT "default to utility".
export const mapTemplateCategory = rawCategory => {
  if (rawCategory === null || rawCategory === undefined || rawCategory === '') {
    return null;
  }
  const upper = String(rawCategory).toUpperCase();
  if (upper === 'MARKETING') return 'marketing';
  if (upper === 'AUTHENTICATION') return 'authentication';
  return 'utility';
};

// i18n key for a derived (mapped) template category badge. Only the three enum
// values are ever derived; null is handled by the no-category block, never here.
export const templateCategoryLabelKey = category => {
  const map = {
    marketing: 'DISPARADOR_MGMT.CREATE.FORM.CATEGORY.MARKETING',
    utility: 'DISPARADOR_MGMT.CREATE.FORM.CATEGORY.UTILITY',
    authentication: 'DISPARADOR_MGMT.CREATE.FORM.CATEGORY.AUTHENTICATION',
  };
  return map[category] || null;
};

// Disparo status enum (mirrors app/models/disparo.rb). Unknown values fall back
// to the raw value so a future status never renders as blank.
export const statusLabelKey = status => {
  const map = {
    draft: 'DISPARADOR_MGMT.STATUS.DRAFT',
    scheduled: 'DISPARADOR_MGMT.STATUS.SCHEDULED',
    running: 'DISPARADOR_MGMT.STATUS.RUNNING',
    paused: 'DISPARADOR_MGMT.STATUS.PAUSED',
    completed: 'DISPARADOR_MGMT.STATUS.COMPLETED',
    failed: 'DISPARADOR_MGMT.STATUS.FAILED',
    cancelled: 'DISPARADOR_MGMT.STATUS.CANCELLED',
  };
  return map[status] || null;
};

// Disparo target state enum (mirrors app/models/disparo_target.rb). Distinct
// from the disparo `status` enum above — a target is pending/queued/skipped/
// cancelled, never draft/scheduled/etc. Unknown values fall back to the raw
// value so a future state never renders as blank.
export const targetStateLabelKey = state => {
  const map = {
    pending: 'DISPARADOR_MGMT.TARGETS.STATE.PENDING',
    queued: 'DISPARADOR_MGMT.TARGETS.STATE.QUEUED',
    skipped: 'DISPARADOR_MGMT.TARGETS.STATE.SKIPPED',
    cancelled: 'DISPARADOR_MGMT.TARGETS.STATE.CANCELLED',
  };
  return map[state] || null;
};

// Eligibility skip-reason keys (mirrors Disparos::EligibilityEngine::PRECEDENCE).
const SKIP_REASON_KEYS = {
  unsupported_inbox_provider:
    'DISPARADOR_MGMT.DRY_RUN.SKIP_REASONS.UNSUPPORTED_INBOX_PROVIDER',
  inbox_not_approved: 'DISPARADOR_MGMT.DRY_RUN.SKIP_REASONS.INBOX_NOT_APPROVED',
  missing_phone: 'DISPARADOR_MGMT.DRY_RUN.SKIP_REASONS.MISSING_PHONE',
  invalid_phone: 'DISPARADOR_MGMT.DRY_RUN.SKIP_REASONS.INVALID_PHONE',
  opt_out_lgpd: 'DISPARADOR_MGMT.DRY_RUN.SKIP_REASONS.OPT_OUT_LGPD',
  label_agente_off_permanente:
    'DISPARADOR_MGMT.DRY_RUN.SKIP_REASONS.LABEL_AGENTE_OFF_PERMANENTE',
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

// Returns the i18n key for a skip reason, or null when the key is unknown so the
// caller can fall back to the raw value rather than rendering an empty cell.
export const skipReasonLabelKey = reason => SKIP_REASON_KEYS[reason] || null;

// Turns the by_skip_reason map into a sorted (desc by count) list for rendering.
export const skipReasonRows = (bySkipReason = {}) =>
  Object.entries(bySkipReason)
    .map(([reason, count]) => ({ reason, count }))
    .sort((a, b) => b.count - a.count);

// estimated_cost_cents is null when no price is configured (unknown_price). Only
// a non-null integer should be rendered as a real price.
export const hasKnownCost = estimatedCostCents =>
  estimatedCostCents !== null && estimatedCostCents !== undefined;

export const formatCostCents = estimatedCostCents =>
  `$${(estimatedCostCents / 100).toFixed(2)}`;

// Defaults for the per-account Disparador rule bindings. These MIRROR the
// constants in app/services/disparos/rules_config.rb — when a key is unset the
// engine resolves to these exact values, so the settings UI shows them as the
// effective value rather than a blank field.
export const DISPARADOR_SETTINGS_DEFAULTS = {
  opt_out_label: 'agente-off-permanente',
  kanban_opt_out_steps: ['9'],
  opt_out_lgpd_key: 'opt_out_lgpd',
  followup_locked_key: 'followup_locked',
  window_closes_at_key: 'window_closes_at',
  kanban_step_key: 'kanban_step',
  whatsapp_invalid_at_key: 'whatsapp_invalid_at',
  dedup_window_days: 7,
  whatsapp_invalid_window_days: 30,
};

// String-key bindings (opt-out label + the 5 custom-attribute keys). A blank
// stored value falls back to the default — mirrors RulesConfig#fetch.
const STRING_BINDING_KEYS = [
  'opt_out_label',
  'opt_out_lgpd_key',
  'followup_locked_key',
  'window_closes_at_key',
  'kanban_step_key',
  'whatsapp_invalid_at_key',
];

// Integer window bindings. A blank or non-positive stored value falls back to
// the default — mirrors RulesConfig#fetch_days.
const WINDOW_BINDING_KEYS = [
  'dedup_window_days',
  'whatsapp_invalid_window_days',
];

// Resolves the EFFECTIVE bindings for an account's stored disparador_settings,
// applying the same blank/positive fallback semantics as RulesConfig so the form
// prefills with the values the engine would actually use. A nil/empty sub-hash
// yields the full defaults.
export const resolveDisparadorSettings = (stored = {}) => {
  const source = stored || {};
  const resolved = {};

  STRING_BINDING_KEYS.forEach(key => {
    const value = source[key];
    resolved[key] =
      typeof value === 'string' && value.trim() !== ''
        ? value
        : DISPARADOR_SETTINGS_DEFAULTS[key];
  });

  WINDOW_BINDING_KEYS.forEach(key => {
    const value = Number(source[key]);
    resolved[key] =
      Number.isInteger(value) && value > 0
        ? value
        : DISPARADOR_SETTINGS_DEFAULTS[key];
  });

  const steps = source.kanban_opt_out_steps;
  resolved.kanban_opt_out_steps =
    Array.isArray(steps) && steps.length
      ? steps.map(String)
      : [...DISPARADOR_SETTINGS_DEFAULTS.kanban_opt_out_steps];

  return resolved;
};
