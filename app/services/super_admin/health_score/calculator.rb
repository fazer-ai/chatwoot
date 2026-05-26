# Orchestrates the 5 metrics, applies the weight model, normalizes per
# group (Outcomes / Operational / Engagement), runs the kill-clauses and
# persists a daily snapshot in `account_health_scores`.
#
# Weight redistribution: when a metric returns `missing: true`, its weight
# is removed and the remaining metrics' weights are renormalized
# proportionally (the same fact, expressed two ways: either you give them
# extra weight, or you divide weighted_sum by available_weight instead of
# the constant 100). Either is mathematically equivalent — we use the
# divide-by-available approach because it's shorter and matches how each
# group also normalizes itself for the per-group score.
#
# Kill clauses cap the final score regardless of the weighted result:
#   - all WhatsApp inboxes currently disconnected -> ≤40
#   - zero agent activity in last 14d             -> ≤30
class SuperAdmin::HealthScore::Calculator
  WEIGHTS = {
    ai_active_rate: 30,
    handoff_rate: 10,
    inbox_uptime: 25,
    daily_agent_activity: 25,
    manager_engagement: 10
  }.freeze

  GROUPS = {
    outcomes: %i[ai_active_rate handoff_rate],
    operational: %i[inbox_uptime],
    engagement: %i[daily_agent_activity manager_engagement]
  }.freeze

  METRIC_CLASSES = {
    ai_active_rate: SuperAdmin::HealthScore::Metrics::AiActiveRate,
    handoff_rate: SuperAdmin::HealthScore::Metrics::HandoffRate,
    inbox_uptime: SuperAdmin::HealthScore::Metrics::InboxUptime,
    daily_agent_activity: SuperAdmin::HealthScore::Metrics::DailyAgentActivity,
    manager_engagement: SuperAdmin::HealthScore::Metrics::ManagerEngagement
  }.freeze

  attr_reader :account, :on

  def initialize(account, on: Date.current)
    @account = account
    @on = on
  end

  def perform
    metric_results = compute_metrics
    weighted_score = weighted_average(metric_results)
    final_score, kill_clause = apply_kill_clauses(weighted_score, metric_results)
    breakdown = build_breakdown(metric_results, weighted_score, kill_clause)
    persist!(final_score, breakdown)
  end

  private

  def compute_metrics
    METRIC_CLASSES.transform_values do |klass|
      klass.new(account, on: on).compute
    end
  end

  def weighted_average(metric_results)
    available = metric_results.reject { |_, r| r[:missing] }
    return 0 if available.empty?

    available_weight = available.keys.sum { |k| WEIGHTS[k] }
    weighted_sum = available.sum { |k, r| r[:sub_score] * WEIGHTS[k] }
    (weighted_sum.to_f / available_weight).round
  end

  def apply_kill_clauses(weighted_score, metric_results)
    uptime = metric_results[:inbox_uptime]
    activity = metric_results[:daily_agent_activity]

    return [[weighted_score, 40].min, 'all_whatsapp_inboxes_disconnected'] if !uptime[:missing] && uptime.dig(:raw, :all_disconnected)

    return [[weighted_score, 30].min, 'no_agent_activity'] if !activity[:missing] && activity.dig(:raw, :active_days).to_i.zero?

    [weighted_score, nil]
  end

  def build_breakdown(metric_results, weighted_score, kill_clause)
    {
      weighted_score: weighted_score,
      kill_clause: kill_clause,
      account_age_days: (on - account.created_at.to_date).to_i,
      phase: account_phase,
      metrics: serialize_metrics(metric_results),
      groups: build_group_breakdown(metric_results)
    }
  end

  def account_phase
    age = (on - account.created_at.to_date).to_i
    return 'implementation' if age < SuperAdmin::HealthScore::Metrics::AiActiveRate::IMPLEMENTATION_PHASE_DAYS
    return 'early_operational' if age < SuperAdmin::HealthScore::Metrics::AiActiveRate::EARLY_OPERATIONAL_PHASE_DAYS

    'mature'
  end

  def serialize_metrics(metric_results)
    metric_results.each_with_object({}) do |(key, result), acc|
      acc[key] = {
        weight_normal: WEIGHTS[key],
        weight_applied: result[:missing] ? 0 : effective_weight(key, metric_results),
        sub_score: result[:sub_score],
        missing: result[:missing],
        reason: result[:reason],
        raw: result[:raw]
      }
    end
  end

  # The "effective weight" a metric contributes to the final score is its
  # normal weight scaled by 100 / (sum of available weights). Useful for the
  # UI to show "this metric counted as X%" when others are missing.
  def effective_weight(key, metric_results)
    available_weight = metric_results.reject { |_, r| r[:missing] }.keys.sum { |k| WEIGHTS[k] }
    return WEIGHTS[key] if available_weight.zero?

    ((WEIGHTS[key].to_f / available_weight) * 100).round(1)
  end

  def build_group_breakdown(metric_results)
    GROUPS.each_with_object({}) do |(group, keys), acc|
      group_total_weight = keys.sum { |k| WEIGHTS[k] }
      available = keys.reject { |k| metric_results[k][:missing] }

      if available.empty?
        acc[group] = { weight_total: group_total_weight, sub_score_normalized: nil, missing: true }
        next
      end

      available_weight = available.sum { |k| WEIGHTS[k] }
      weighted_sum = available.sum { |k| metric_results[k][:sub_score] * WEIGHTS[k] }
      normalized = (weighted_sum.to_f / available_weight).round
      acc[group] = { weight_total: group_total_weight, sub_score_normalized: normalized, missing: false }
    end
  end

  def persist!(score, breakdown)
    record = AccountHealthScore.find_or_initialize_by(account_id: account.id, captured_on: on)
    record.assign_attributes(score: score, breakdown: breakdown)
    record.save!
    record
  end
end
