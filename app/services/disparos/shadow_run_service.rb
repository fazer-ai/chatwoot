# frozen_string_literal: true

# Beta 0 "Disparador Cloud Shadow" — Shadow Run Service.
#
# Persists the per-row target set the shadow run produces. For
# each candidate conversation it runs the EligibilityEngine and UPSERTs ONE
# DisparoTarget keyed by (disparo_id, conversation_id, contact_id), then appends
# a DisparoEvent describing the (would-be) outcome.
#
# Hard scope boundaries (do NOT break):
#   - NEVER sends, NEVER calls Meta, NEVER instantiates a Meta client.
#   - NEVER creates a Chatwoot Message or Conversation.
#   - The ONLY writes are to disparo_targets + disparo_events (Beta 0 tables).
#   - Reads source tables only (via AudienceResolver / EligibilityEngine).
#   - shadow_run = true on EVERY persisted target (eligible AND skipped) — AC8.
#
# Grain: one (conversation_id, contact_id) pair.
#   - eligible? -> state = queued (the would-be send, shadow); no skip reasons.
#   - skipped   -> state = skipped; primary_skip_reason + skip_reasons[] kept.
# BOTH are persisted: the full set is kept and the eligible subset is derived
# from `state` (AC7).
#
# Idempotency (AC46): re-running on the SAME disparo is an in-place UPSERT via
# find_or_initialize_by((disparo_id, conversation_id, contact_id)). A second run
# never duplicates rows and re-converges every target onto the latest evaluation
# (a candidate that turned ineligible flips queued -> skipped in place). The
# unique index (disparo_id, conversation_id, contact_id) is the backstop.
#
# Event-append policy: an event is appended ONLY when the persisted state
# changes — creation counts as a change. This keeps disparo_events a clean
# state-transition log and bounds growth to <=1 event per transition per target,
# so re-runs do not bloat the append-only table.
#
# Intra-run guard (`already_in_shadow_run`): a Set of (conversation_id,
# contact_id) seen WITHIN this run. The second occurrence in one candidate
# stream is skipped from re-processing (defensive — AudienceResolver already
# returns one row per conversation). It is NOT a persisted skip_reason.
class Disparos::ShadowRunService
  include Disparos::RunnableDisparo

  Summary = Struct.new(:total_targets, :eligible, :skipped, :created, :updated, keyword_init: true)

  def initialize(now: Time.current, snapshot_id: nil)
    @now = now
    @snapshot_id = snapshot_id
  end

  def perform(disparo)
    validate_runnable!(disparo, CustomExceptions::Disparos::InvalidShadowRun)
    # GAP B: the shadow run may ONLY persist the set the operator approved in a
    # dry-run preview. Validate the snapshot (exists, belongs to this disparo, not
    # expired, config unchanged) BEFORE touching any target row, so a stale or
    # drifted approval rolls the (empty) transaction back cleanly.
    validate_snapshot!(disparo)

    # Run-level telemetry: ids + counts only (no phone/token/raw SHA) — §Observability / US20.
    ActiveSupport::Notifications.instrument('disparos.shadow_run_started', disparo_id: disparo.id)

    # Resolve the per-account rule bindings ONCE per run and inject them into the
    # engine; the engine never reads account.settings per-conversation.
    @rules_config = Disparos::RulesConfig.new(disparo.account)

    summary = process_candidates(disparo)

    ActiveSupport::Notifications.instrument(
      'disparos.shadow_run_completed',
      disparo_id: disparo.id, total_targets: summary[:total_targets], eligible: summary[:eligible], skipped: summary[:skipped]
    )

    Summary.new(**summary)
  end

  private

  # Iterates the resolved audience, intra-run de-duping by grain, and upserts one
  # target per (conversation, contact). Returns the running summary hash.
  def process_candidates(disparo)
    candidates = Disparos::AudienceResolver.new(
      account: disparo.account, filter: filter_for(disparo),
      inbox_ids: disparo.disparo_inboxes.pluck(:inbox_id), conversation_status: disparo.conversation_status
    ).perform
    summary = { total_targets: 0, eligible: 0, skipped: 0, created: 0, updated: 0 }
    seen = Set.new

    candidates.each do |conversation|
      # Intra-run de-dup: skip the second occurrence of the same grain in ONE run.
      next unless seen.add?([conversation.id, conversation.contact_id])

      upsert_target(disparo, conversation, evaluate(disparo, conversation), summary)
    end

    summary
  end

  # GAP B gate. Raises InvalidShadowRun unless the approved dry-run snapshot is
  # present, belongs to THIS disparo, is not expired, and was computed under the
  # disparo's CURRENT config (fingerprint match). The recalculated rows are still
  # authoritative for persistence; the snapshot is the APPROVAL gate (TTL +
  # fingerprint), not the row source — the snapshot stores only aggregates.
  def validate_snapshot!(disparo)
    raise CustomExceptions::Disparos::InvalidShadowRun if @snapshot_id.blank?

    snapshot = disparo.disparo_audience_snapshots.find_by(id: @snapshot_id)
    raise CustomExceptions::Disparos::InvalidShadowRun if snapshot.nil?
    raise CustomExceptions::Disparos::InvalidShadowRun if snapshot.expires_at.nil? || snapshot.expires_at <= @now
    raise CustomExceptions::Disparos::InvalidShadowRun if snapshot.config_fingerprint != Disparos::ConfigFingerprint.for(disparo)
  end

  def evaluate(disparo, conversation)
    Disparos::EligibilityEngine.new(
      conversation: conversation, template_name: disparo.template_name, now: @now,
      template_category: disparo.template_category, config: @rules_config
    ).perform
  end

  def upsert_target(disparo, conversation, result, summary)
    target = DisparoTarget.find_or_initialize_by(disparo_id: disparo.id, conversation_id: conversation.id, contact_id: conversation.contact_id)
    was_new = target.new_record?

    assign_outcome(target, result)
    # dispatch_id is intentionally left untouched: the DB default gen_random_uuid()
    # fills it on insert and rewriting it on update is a unique-index landmine.
    target.assign_attributes(shadow_run: true, inbox_id: conversation.inbox_id, phone_present: conversation.contact&.phone_number.present?)

    state_changed = target.state_changed? # MUST be captured BEFORE save! — dirty tracking resets on save.
    target.save!
    append_event(target, result) if was_new || state_changed
    # Per-target telemetry: fires for EVERY processed candidate (run telemetry, not the
    # change-only transition log). ids + skip-reason enums only (no PII) — §Observability / US20.
    instrument_target(disparo, target, result)

    tally(summary, result, was_new)
  end

  def instrument_target(disparo, target, result)
    if result.eligible?
      ActiveSupport::Notifications.instrument('disparos.target_queued_shadow',
                                              disparo_id: disparo.id, disparo_target_id: target.id, conversation_id: target.conversation_id)
    else
      ActiveSupport::Notifications.instrument(
        'disparos.target_skipped',
        disparo_id: disparo.id, disparo_target_id: target.id, conversation_id: target.conversation_id,
        primary_skip_reason: result.primary_skip_reason, skip_reasons: result.skip_reasons
      )
    end
  end

  def assign_outcome(target, result)
    if result.eligible?
      target.assign_attributes(state: :queued, primary_skip_reason: nil, skip_reasons: [])
    else
      target.assign_attributes(state: :skipped, primary_skip_reason: result.primary_skip_reason, skip_reasons: result.skip_reasons)
    end
  end

  def append_event(target, result)
    if result.eligible?
      DisparoEvent.create!(disparo_target: target, event_type: :queued, payload: {})
    else
      DisparoEvent.create!(disparo_target: target, event_type: :skipped,
                           payload: { primary_skip_reason: result.primary_skip_reason, skip_reasons: result.skip_reasons })
    end
  end

  def tally(summary, result, was_new)
    summary[:total_targets] += 1
    result.eligible? ? summary[:eligible] += 1 : summary[:skipped] += 1
    was_new ? summary[:created] += 1 : summary[:updated] += 1
  end

  # validate_runnable! / filter_for are provided by Disparos::RunnableDisparo.
end
