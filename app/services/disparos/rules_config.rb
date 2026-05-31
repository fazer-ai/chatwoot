# frozen_string_literal: true

# Beta 0 "Disparador Cloud Shadow" — per-account Rules Config (value object).
#
# Resolves the EligibilityEngine's rule BINDINGS (opt-out label, opt-out kanban
# stages, custom-attribute keys and the dedup/whatsapp-invalid windows) for ONE
# account. Each binding is account-editable via `account.settings`
# (the jsonb `disparador_settings` sub-hash); when a key is unset the DEFAULT —
# the value the engine used as a hardcoded constant before this was made
# configurable — is returned. So a nil account (or an empty sub-hash) reproduces
# today's behavior EXACTLY.
#
# Resolution is done ONCE per run (the Dry/Shadow services build this from
# `disparo.account` and inject it). The engine never reads `account.settings`
# per-conversation; it reads the resolved bindings off this object.
#
# NOT configurable here (protocol/format, not per-account policy): the
# `bulk_template_<name>_sent_at` dedup key, E.164 format, the Cloud provider
# value and the approved-template status — those stay hardcoded in the engine.
class Disparos::RulesConfig
  SETTINGS_KEY = 'disparador_settings'

  # DEFAULTS — these are the exact values the EligibilityEngine used as constants
  # before the bindings became per-account configurable. Unset config => default
  # => today's behavior.
  DEFAULT_OPT_OUT_LABEL = 'agente-off-permanente'
  DEFAULT_KANBAN_OPT_OUT_STEPS = ['9'].freeze
  DEFAULT_OPT_OUT_LGPD_KEY = 'opt_out_lgpd'
  DEFAULT_FOLLOWUP_LOCKED_KEY = 'followup_locked'
  DEFAULT_WINDOW_CLOSES_AT_KEY = 'window_closes_at'
  DEFAULT_KANBAN_STEP_KEY = 'kanban_step'
  DEFAULT_WHATSAPP_INVALID_AT_KEY = 'whatsapp_invalid_at'
  DEFAULT_DEDUP_WINDOW_DAYS = 7
  DEFAULT_WHATSAPP_INVALID_WINDOW_DAYS = 30

  def initialize(account = nil)
    @overrides = extract_overrides(account)
  end

  # Label title for the permanent agent-off opt-out. Compared case-insensitively
  # by the engine; the default stays lowercase.
  def opt_out_label
    fetch('opt_out_label', DEFAULT_OPT_OUT_LABEL)
  end

  # Array of kanban_step values (compared as STRINGS) that mean "opted out".
  # Generalizes the single Stage-9 to allow multiple opt-out stages.
  def kanban_opt_out_steps
    raw = @overrides['kanban_opt_out_steps']
    return DEFAULT_KANBAN_OPT_OUT_STEPS if raw.blank?

    Array(raw).map(&:to_s)
  end

  def opt_out_lgpd_key
    fetch('opt_out_lgpd_key', DEFAULT_OPT_OUT_LGPD_KEY)
  end

  def followup_locked_key
    fetch('followup_locked_key', DEFAULT_FOLLOWUP_LOCKED_KEY)
  end

  def window_closes_at_key
    fetch('window_closes_at_key', DEFAULT_WINDOW_CLOSES_AT_KEY)
  end

  def kanban_step_key
    fetch('kanban_step_key', DEFAULT_KANBAN_STEP_KEY)
  end

  def whatsapp_invalid_at_key
    fetch('whatsapp_invalid_at_key', DEFAULT_WHATSAPP_INVALID_AT_KEY)
  end

  def dedup_window
    fetch_days('dedup_window_days', DEFAULT_DEDUP_WINDOW_DAYS).days
  end

  def whatsapp_invalid_window
    fetch_days('whatsapp_invalid_window_days', DEFAULT_WHATSAPP_INVALID_WINDOW_DAYS).days
  end

  private

  def extract_overrides(account)
    raw = account&.settings&.dig(SETTINGS_KEY)
    raw.is_a?(Hash) ? raw.stringify_keys : {}
  end

  # A blank/absent override falls back to the default so a half-filled config
  # never silently breaks a binding.
  def fetch(key, default)
    @overrides[key].presence || default
  end

  # Windows are stored as integer days; a blank/non-positive override falls back
  # to the default rather than collapsing the window to zero.
  def fetch_days(key, default)
    days = @overrides[key].to_i
    days.positive? ? days : default
  end
end
