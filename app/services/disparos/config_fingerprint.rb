# frozen_string_literal: true

# Beta 0 "Disparador Cloud Shadow" — config FINGERPRINT helper.
#
# A deterministic SHA over the disparo's config dimensions, used by GAP B to gate
# the shadow run: DryRunService stores this on the snapshot it writes, and
# ShadowRunService recomputes it from the disparo's CURRENT config and refuses to
# run if it drifted from the approved snapshot. So an operator can never approve
# one preview and persist a set built from a different template / inbox set /
# audience filter / conversation status.
#
# Dimensions (the config that changes WHICH leads get persisted):
#   - template_name
#   - template_category (the enum reader: 'marketing' / 'utility' / 'authentication')
#   - audience_filter   (canonicalized: keys + array values sorted, so equal
#                        filters in any order hash identically)
#   - inbox_ids         (disparo.disparo_inboxes.pluck(:inbox_id), SORTED)
#   - conversation_status ('open' / 'all')
#   - account_rules     (the resolved per-account Disparos::RulesConfig bindings:
#                        opt-out label, opt-out kanban stages, the custom-attribute
#                        keys and the dedup/whatsapp-invalid windows). Eligibility
#                        depends on these too, so a change to account.disparador_settings
#                        between dry-run and shadow-run MUST drift the hash — otherwise
#                        the shadow run would recompute a DIFFERENT eligible set than
#                        the operator approved (GAP B via the account-settings vector).
#
# This is NOT the removed wf15 filter_digest — it is new, simple, and self-contained.
class Disparos::ConfigFingerprint
  def self.for(disparo)
    new(disparo).digest
  end

  def initialize(disparo)
    @disparo = disparo
  end

  def digest
    Digest::SHA256.hexdigest(canonical_payload.to_json)
  end

  private

  def canonical_payload
    {
      template_name: @disparo.template_name,
      template_category: @disparo.template_category,
      audience_filter: canonical_filter,
      inbox_ids: @disparo.disparo_inboxes.pluck(:inbox_id).sort,
      conversation_status: @disparo.conversation_status,
      account_rules: canonical_account_rules
    }
  end

  # The resolved per-account rule bindings, in a deterministic, canonical shape.
  # Resolved INTERNALLY from @disparo.account via the SAME resolver the engine
  # uses (Disparos::RulesConfig), so DryRunService and ShadowRunService — which
  # both already call ConfigFingerprint.for(disparo) — fold these in identically
  # with no per-service threading. A default account (no disparador_settings)
  # yields the RulesConfig defaults, so the digest is unchanged from today's.
  #
  # Determinism: the keys are written as a code literal (stable order);
  # kanban_opt_out_steps is sorted; the windows are emitted as Integer SECONDS
  # (Duration#to_i) so an ActiveSupport::Duration never leaks into the JSON.
  def canonical_account_rules
    config = Disparos::RulesConfig.new(@disparo.account)
    {
      opt_out_label: config.opt_out_label,
      kanban_opt_out_steps: config.kanban_opt_out_steps.sort,
      opt_out_lgpd_key: config.opt_out_lgpd_key,
      followup_locked_key: config.followup_locked_key,
      window_closes_at_key: config.window_closes_at_key,
      kanban_step_key: config.kanban_step_key,
      whatsapp_invalid_at_key: config.whatsapp_invalid_at_key,
      dedup_window_seconds: config.dedup_window.to_i,
      whatsapp_invalid_window_seconds: config.whatsapp_invalid_window.to_i
    }
  end

  # Canonicalize the audience_filter so two filters that are equal up to key/value
  # ordering produce the same fingerprint: sort the hash by key and sort every
  # array value. Beta 0 filter values are arrays of strings (kanban_steps, label).
  def canonical_filter
    filter = (@disparo.audience_filter || {}).stringify_keys
    filter.keys.sort.to_h do |key|
      value = filter[key]
      [key, value.is_a?(Array) ? value.map(&:to_s).sort : value]
    end
  end
end
