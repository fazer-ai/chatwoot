# frozen_string_literal: true

# Beta 0 "Disparador Cloud Shadow" — Dry Run Service.
#
# Read-only / shadow orchestration of a single dispatch's audience. It fetches
# candidates (AudienceResolver), evaluates each one (EligibilityEngine),
# aggregates eligible/skipped counts plus skip-reason and per-inbox breakdowns,
# estimates cost (CostEstimator) and persists ONE aggregate
# DisparoAudienceSnapshot row.
#
# Hard scope boundaries (do NOT break):
#   - NEVER creates a DisparoTarget (that is the future Shadow Run Service).
#   - NEVER creates a Chatwoot Message or Conversation.
#   - NEVER calls Meta or any send path (there is no Meta client here).
#   - Reads source tables only; the single write is the snapshot row.
#
# Aggregation grain: one candidate conversation.
#   - by_skip_reason counts EVERY applicable reason across ALL candidates'
#     `skip_reasons[]` (not just primary). A candidate failing two rules
#     increments two buckets, so opt-out is never undercounted (AC44).
#   - by_inbox counts ELIGIBLE candidates grouped by their conversation's
#     inbox_id (eligible-per-inbox).
#
# Cost is injectable (`cost_estimator:`) so the integer/nil paths are both
# exercisable: the default estimator is unconfigured (returns nil/unknown_price).
class Disparos::DryRunService
  include Disparos::RunnableDisparo

  SNAPSHOT_TTL = 15.minutes

  Summary = Struct.new(
    :total_eligible,
    :total_skipped,
    :by_skip_reason,
    :by_inbox,
    :estimated_cost_cents,
    :cost_source,
    :snapshot,
    keyword_init: true
  )

  def initialize(now: Time.current, cost_estimator: Disparos::CostEstimator.new)
    @now = now
    @cost_estimator = cost_estimator
  end

  def perform(disparo)
    validate_runnable!(disparo, CustomExceptions::Disparos::InvalidDryRun)
    # Run-level telemetry: ids + counts only (no phone/token/raw SHA) — §Observability / US20.
    ActiveSupport::Notifications.instrument('disparos.dry_run_started', disparo_id: disparo.id)

    # Resolve the per-account rule bindings ONCE per run and inject them into the
    # engine; the engine never reads account.settings per-conversation.
    @rules_config = Disparos::RulesConfig.new(disparo.account)
    @template_category = disparo.template_category
    filter = filter_for(disparo)
    agg = aggregate(resolve_candidates(disparo, filter), disparo.template_name)
    estimated_cost_cents = @cost_estimator.perform(eligible_count: agg[:total_eligible], category: disparo.template_category)
    snapshot = persist_snapshot(disparo, filter, agg, estimated_cost_cents)
    instrument_completed(disparo, agg)

    Summary.new(
      total_eligible: agg[:total_eligible],
      total_skipped: agg[:total_skipped],
      by_skip_reason: agg[:by_skip_reason],
      by_inbox: agg[:by_inbox],
      estimated_cost_cents: estimated_cost_cents,
      cost_source: @cost_estimator.source,
      snapshot: snapshot
    )
  end

  private

  def resolve_candidates(disparo, filter)
    Disparos::AudienceResolver.new(
      account: disparo.account, filter: filter,
      inbox_ids: disparo.disparo_inboxes.pluck(:inbox_id), conversation_status: disparo.conversation_status
    ).perform
  end

  def instrument_completed(disparo, agg)
    ActiveSupport::Notifications.instrument(
      'disparos.dry_run_completed',
      disparo_id: disparo.id, total_eligible: agg[:total_eligible], total_skipped: agg[:total_skipped]
    )
  end

  # Iterates every candidate once and tallies eligible/skipped counts, the
  # per-inbox eligible breakdown and the ALL-reasons skip breakdown (AC44).
  def aggregate(candidates, template_name)
    agg = { total_eligible: 0, total_skipped: 0, by_skip_reason: Hash.new(0), by_inbox: Hash.new(0) }

    candidates.each do |conversation|
      result = Disparos::EligibilityEngine.new(
        conversation: conversation, template_name: template_name, now: @now,
        template_category: @template_category, config: @rules_config
      ).perform

      if result.eligible?
        agg[:total_eligible] += 1
        agg[:by_inbox][conversation.inbox_id.to_s] += 1
      else
        agg[:total_skipped] += 1
        result.skip_reasons.each { |reason| agg[:by_skip_reason][reason] += 1 }
      end
    end

    agg
  end

  # validate_runnable! / filter_for are provided by Disparos::RunnableDisparo.

  def persist_snapshot(disparo, filter, agg, estimated_cost_cents)
    DisparoAudienceSnapshot.create!(
      disparo: disparo,
      filter_dsl: filter,
      inbox_ids: disparo.disparo_inboxes.pluck(:inbox_id),
      total_eligible: agg[:total_eligible],
      by_skip_reason: agg[:by_skip_reason],
      by_inbox: agg[:by_inbox],
      estimated_cost_cents: estimated_cost_cents,
      expires_at: @now + SNAPSHOT_TTL,
      # GAP B: pin the config this preview was computed under, so ShadowRun can
      # refuse to persist if the disparo's config drifts before approval.
      config_fingerprint: Disparos::ConfigFingerprint.for(disparo)
    )
  end
end
