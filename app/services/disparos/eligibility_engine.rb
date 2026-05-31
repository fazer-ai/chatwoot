# frozen_string_literal: true

# Beta 0 "Disparador Cloud Shadow" — Eligibility Engine.
#
# THE single enforcement point. Given one candidate conversation (with its
# contact and inbox), the target template_name and an injectable `now`, it
# decides whether that conversation is `eligible` or `skipped` and, when
# skipped, returns EVERY applicable skip reason plus the highest-precedence one.
#
# Scope (read-only / shadow): this engine does NOT fetch candidates (that is
# AudienceResolver), does NOT persist targets, does NOT run dry-run/shadow and
# NEVER writes to the DB or calls Meta. It only evaluates and returns a
# Disparos::EligibilityResult.
#
# Grain: one conversation. All rules are evaluated; nothing short-circuits, so a
# lead that fails several rules carries ALL of them in `skip_reasons` (AC44).
# `primary_skip_reason` is then picked by PRECEDENCE.
class Disparos::EligibilityEngine
  include Disparos::TimeParsing

  # --- CONTRACT constants -------------------------------------------------
  # Production-mapped values live here in ONE place. Each is provisional and
  # MUST be reconciled against a sanitized prod snapshot before Phase 5.
  #
  # The rule BINDINGS (opt-out label, opt-out kanban stages, custom-attribute
  # keys and the dedup/whatsapp-invalid windows) are now PER-ACCOUNT editable and
  # live on the injected `Disparos::RulesConfig` (their DEFAULTS — the values this
  # engine used to hardcode — live there too). The constants that remain below
  # are protocol/format, NOT per-account policy.

  # CONTRACT — reconcile vs sanitized prod snapshot before Phase 5
  # Legacy dedup key, scoped per template name:
  #   custom_attributes["bulk_template_#{template_name}_sent_at"]
  # (A generic `template_last_sent_*` family is a noted contract alternative but
  # is intentionally NOT implemented in Beta 0.)
  def self.dedup_key(template_name)
    Disparos::BulkMarker.key(template_name)
  end

  # WhatsApp Cloud provider value on Channel::Whatsapp. The fork also ships
  # `default` (360dialog), `baileys` and `zapi`, none of which are Cloud.
  CLOUD_PROVIDER = 'whatsapp_cloud'

  # Meta's per-template approval status. The synced `channel.message_templates`
  # jsonb array stores this with inconsistent casing ('approved' vs 'APPROVED'),
  # so the allowlist check is case-insensitive (status.to_s.downcase).
  APPROVED_TEMPLATE_STATUS = 'approved'

  # Reuses Contact#phone_number's canonical E.164 body `\+[1-9]\d{1,14}\z`.
  # phonelib is NOT a dependency of this fork, so we reuse this regex instead of
  # hand-rolling a new one. We add a leading `\A` anchor (Contact's validation
  # relies on a full-string `format:` match) so a leading-garbage value cannot
  # pass the standalone `match?` check used here.
  E164_FORMAT = /\A\+[1-9]\d{1,14}\z/

  # Highest-precedence first. `primary_skip_reason` is the first of these that
  # appears in `skip_reasons`. Reconciled with wf15 (W2): the permanent
  # agente-off label now outranks opt_out_lgpd, and the two new dedup reasons
  # (marketing_cooldown_7d, whatsapp_invalid_30d) sit at the end.
  PRECEDENCE = %w[
    unsupported_inbox_provider
    inbox_not_approved
    missing_phone
    invalid_phone
    label_agente_off_permanente
    opt_out_lgpd
    stage_opt_out
    followup_locked
    invalid_window_closes_at
    window_incompatible
    template_sent_last_7d
    marketing_cooldown_7d
    whatsapp_invalid_30d
  ].freeze

  MARKETING_CATEGORY = 'marketing'

  # template_category arrives as a string from the disparo enum reader but as a
  # symbol from direct callers (and the default). Normalize to a string once so
  # the `== 'marketing'` comparison holds either way. `config` is the resolved
  # per-account Disparos::RulesConfig — its default (no account) reproduces the
  # original hardcoded bindings, so an omitted `config:` is today's behavior.
  def initialize(conversation:, template_name:, now: Time.current, template_category: :utility, config: Disparos::RulesConfig.new)
    @conversation = conversation
    @template_name = template_name
    @now = now
    @template_category = template_category.to_s
    @config = config
  end

  def perform
    reasons = collect_skip_reasons
    Disparos::EligibilityResult.new(reasons, PRECEDENCE.find { |reason| reasons.include?(reason) })
  end

  private

  # Single-reason predicates, in PRECEDENCE order. Phone (missing/invalid) and
  # window (invalid/incompatible) are multi-valued and handled separately. Each
  # entry is [reason, predicate]; the reason is added iff the predicate is true.
  # All single-reason skips (including followup_locked, a kept opt-out) are
  # UNCONDITIONAL — there is no strictness toggle gating them.
  SINGLE_REASON_CHECKS = [
    ['unsupported_inbox_provider', :unsupported_inbox_provider?],
    ['inbox_not_approved', :inbox_not_approved?],
    ['opt_out_lgpd', :opt_out_lgpd?],
    ['label_agente_off_permanente', :agente_off_label?],
    ['stage_opt_out', :stage_opt_out?],
    ['followup_locked', :followup_locked?],
    ['template_sent_last_7d', :dedup_hit?],
    ['marketing_cooldown_7d', :marketing_cooldown_hit?],
    ['whatsapp_invalid_30d', :whatsapp_invalid_hit?]
  ].freeze

  # Evaluates EVERY rule (no short-circuit) and returns ALL applicable skip
  # reasons. Phone is the only mutually-exclusive dimension; everything stacks.
  def collect_skip_reasons
    reasons = phone_reasons + window_reasons
    SINGLE_REASON_CHECKS.each { |reason, predicate| reasons << reason if send(predicate) }
    reasons
  end

  def unsupported_inbox_provider?
    !cloud_inbox?
  end

  # APPROVED-INBOX ALLOWLIST (reconciliation-delta W1/§4.2): inbox validity is a
  # per-template allowlist derived from the synced templates, NOT a cloud on/off.
  # The cloud precondition is the leading guard so a non-cloud inbox fails ONLY on
  # `unsupported_inbox_provider` (never double-stacks here) and the helper never
  # touches a channel that doesn't carry `message_templates`. A cloud inbox with no
  # approved entry for @template_name fails here instead of passing.
  def inbox_not_approved?
    cloud_inbox? && !template_approved_on_inbox?
  end

  def opt_out_lgpd?
    truthy?(custom_attributes[@config.opt_out_lgpd_key])
  end

  # A kept opt-out: ALWAYS applied (no strictness gate).
  def followup_locked?
    truthy?(custom_attributes[@config.followup_locked_key])
  end

  def cloud_inbox?
    inbox = @conversation.inbox
    inbox&.whatsapp? && inbox.channel&.provider == CLOUD_PROVIDER
  end

  # True iff the inbox's synced `channel.message_templates` (jsonb array of
  # string-keyed hashes) carries an entry whose name == @template_name AND whose
  # status is approved (case-insensitive). nil / the `{}` DB default / a missing
  # entry all read as NOT approved. Only called for a cloud inbox.
  def template_approved_on_inbox?
    templates = @conversation.inbox.channel.message_templates
    return false unless templates.is_a?(Array)

    templates.any? do |template|
      template.is_a?(Hash) && template['name'] == @template_name &&
        template['status'].to_s.downcase == APPROVED_TEMPLATE_STATUS
    end
  end

  # missing and invalid are mutually exclusive on the phone dimension: a blank
  # phone yields only `missing_phone`, never also `invalid_phone`.
  def phone_reasons
    phone = @conversation.contact&.phone_number
    return ['missing_phone'] if phone.blank?
    return ['invalid_phone'] unless E164_FORMAT.match?(phone)

    []
  end

  # Both sides are downcased so the match is case-insensitive: the default label
  # is lowercase, and a custom (possibly mixed-case) opt-out label still matches a
  # mixed-case cached label.
  def agente_off_label?
    @conversation.cached_label_list_array.map(&:downcase).include?(@config.opt_out_label.downcase)
  end

  # jsonb stores kanban_step as text; compared as STRING against the configured
  # opt-out stages (array membership; default ['9']).
  def stage_opt_out?
    @config.kanban_opt_out_steps.include?(custom_attributes[@config.kanban_step_key].to_s)
  end

  def window_reasons
    raw = custom_attributes[@config.window_closes_at_key]
    # CONTRACT — reconcile blank/empty window_closes_at (treated as outside-window => eligible) vs observed wf15 behavior before Phase 5
    return [] if raw.blank?

    parsed = parse_time(raw)
    return ['invalid_window_closes_at'] if parsed.nil?
    return ['window_incompatible'] if parsed > @now

    []
  end

  # CONTACT-MIRROR DEDUP: the per-template marker is now read from BOTH the
  # conversation and the contact custom_attributes. A recent marker on EITHER
  # side trips the single `template_sent_last_7d` reason.
  def dedup_hit?
    key = self.class.dedup_key(@template_name)
    recent_marker?(custom_attributes[key]) || recent_marker?(contact_custom_attributes[key])
  end

  # MARKETING COOLDOWN: only for marketing templates. Any `bulk_template_*_sent_at`
  # marker (ANY template name) on the conversation OR contact, parsing to within
  # the configured dedup window, trips `marketing_cooldown_7d`.
  #
  # INTERIM OVER-BROAD APPROXIMATION (reconciliation-delta §6 — OPEN UNKNOWN):
  # wf15 scopes this cooldown to markers whose OWN template category is MARKETING
  # (via a CATALOG mapping template_name -> category). That catalog does NOT exist
  # yet — delta §6 flags its SOURCE as an open unknown the team still owes a data
  # decision on — so we approximate it as "any recent bulk marker regardless of the
  # marker's category". This is intentionally broader than wf15: a recent UTILITY
  # (non-marketing) marker ALSO trips marketing_cooldown_7d here. This is NOT the
  # final behavior; it stays pinned by a characterization spec so the gap is visible
  # and is corrected once the delta §6 template->category catalog lands. Do NOT
  # mistake this for the reconciled rule.
  def marketing_cooldown_hit?
    return false unless @template_category == MARKETING_CATEGORY

    bulk_marker_values(custom_attributes).any? { |raw| recent_marker?(raw) } ||
      bulk_marker_values(contact_custom_attributes).any? { |raw| recent_marker?(raw) }
  end

  # WHATSAPP-INVALID 30d: contact-level. A `whatsapp_invalid_at` within 30 days
  # of `now` trips `whatsapp_invalid_30d`.
  def whatsapp_invalid_hit?
    recent_marker?(contact_custom_attributes[@config.whatsapp_invalid_at_key], @config.whatsapp_invalid_window)
  end

  # Strict-parses `raw` and returns true iff it falls strictly within `window` of
  # `now`. The `>` boundary is preserved so the exact-window edge stays eligible.
  # `window` defaults to the configured dedup window.
  def recent_marker?(raw, window = @config.dedup_window)
    parsed = parse_time(raw)
    return false if parsed.nil?

    parsed > @now - window
  end

  # Every `bulk_template_<any>_sent_at` value in the given custom_attributes hash.
  def bulk_marker_values(attributes)
    attributes.filter_map { |key, value| value if Disparos::BulkMarker.marker_key?(key) }
  end

  def custom_attributes
    @conversation.custom_attributes || {}
  end

  def contact_custom_attributes
    @conversation.contact&.custom_attributes || {}
  end

  def truthy?(value)
    ActiveModel::Type::Boolean.new.cast(value)
  end
  # parse_time (STRICT ISO8601) is provided by Disparos::TimeParsing.
end
