# % of conversations in the last 30d that have AI active. Reads from the
# `ai_enabled` column for accounts in attribute mode, falls back to the
# absence of the `agente-off` label for accounts still on the legacy mode
# (the two modes coexist while clients migrate).
#
# Three lifecycle phases by account age:
#   0-45 days  -> implementation: metric is `missing`, weight redistributes
#   45-60 days -> early operational: current rate only, no trend
#   60+ days   -> mature: current rate + 0.5 * 30d trend delta
#
# Insufficient volume (< 50 conversations in the window) also marks the
# metric as `missing` so a tiny new account doesn't get artificially scored.
class SuperAdmin::HealthScore::Metrics::AiActiveRate < SuperAdmin::HealthScore::Metrics::Base
  IMPLEMENTATION_PHASE_DAYS = 45
  EARLY_OPERATIONAL_PHASE_DAYS = 60
  MIN_CONVERSATIONS_FOR_SIGNAL = 50

  def compute
    return implementation_phase_missing if account_age_days < IMPLEMENTATION_PHASE_DAYS

    current = window_rate(on - 30, on)
    return insufficient_volume_missing(current) if current[:total] < MIN_CONVERSATIONS_FOR_SIGNAL

    account_age_days < EARLY_OPERATIONAL_PHASE_DAYS ? early_operational_score(current) : mature_score(current)
  end

  private

  def account_age_days
    (on - account.created_at.to_date).to_i
  end

  def implementation_phase_missing
    missing(:account_in_implementation_phase,
            account_age_days: account_age_days,
            active_from_date: account.created_at.to_date + IMPLEMENTATION_PHASE_DAYS)
  end

  def insufficient_volume_missing(current)
    missing(:insufficient_volume, account_age_days: account_age_days, total_conversations: current[:total])
  end

  def early_operational_score(current)
    sub_score = (current[:pct] * 100).clamp(0, 100).round
    present(sub_score, base_raw(current).merge(trend_applied: false))
  end

  def mature_score(current)
    prior = window_rate(on - 60, on - 30)
    trend_delta = current[:pct] - prior[:pct]
    sub_score = ((current[:pct] + (0.5 * trend_delta)) * 100).clamp(0, 100).round
    present(sub_score, base_raw(current).merge(prior_pct: prior[:pct], trend_delta_pct: trend_delta, trend_applied: true))
  end

  def ai_mode
    account.ai_status_uses_attribute? ? 'attribute' : 'legacy_label'
  end

  def base_raw(current)
    { mode: ai_mode, current_pct: current[:pct], total_conversations: current[:total], ai_active_count: current[:active] }
  end

  def window_rate(window_start, window_end)
    scope = conversations_in_window(window_start, window_end)
    total = scope.count
    return { pct: 0.0, total: 0, active: 0 } if total.zero?

    active = ai_active_scope(scope).count
    { pct: active.to_f / total, total: total, active: active }
  end

  def conversations_in_window(window_start, window_end)
    account.conversations.where(created_at: window_start.beginning_of_day..window_end.end_of_day)
  end

  def ai_active_scope(scope)
    return scope.where(ai_enabled: true) if account.ai_status_uses_attribute?

    # Legacy mode: AI is "on" when the `agente-off` label is NOT present.
    scope.where.not(
      id: ActsAsTaggableOn::Tagging
            .joins(:tag)
            .where(taggable_type: 'Conversation', tags: { name: 'agente-off' })
            .select(:taggable_id)
    )
  end
end
