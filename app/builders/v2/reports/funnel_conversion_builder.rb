class V2::Reports::FunnelConversionBuilder
  include DateRangeHelper

  attr_reader :account, :params

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    stages = FunnelStage.active.ordered.to_a
    return { stages: [], kpis: empty_kpis } if stages.empty?

    counts = fetch_distinct_counts(stages.map(&:name))
    stage_rows = build_stage_rows(stages, counts)

    { stages: stage_rows, kpis: build_kpis(stages, counts) }
  end

  private

  # Distinct conversation ids that entered each stage within the period.
  # Reentries by the same conversation (cycle > 1) count once per stage —
  # the funnel chart answers "how many conversations passed through", not
  # "how many entries happened".
  def fetch_distinct_counts(stage_names)
    scope = account.funnel_stage_changes.where(new_stage: stage_names)
    scope = scope.where(created_at: range) if range.present?
    scope.distinct.group(:new_stage).count(:conversation_id)
  end

  def build_stage_rows(stages, counts)
    rows = stages.map { |stage| stage_row(stage, counts[stage.name] || 0) }

    # Conversion / drop-off look at the next stage in the displayed order.
    # The denominator is THIS stage's count: when the next stage has more
    # conversations than this one (entered from outside), conversion legitimately
    # crosses 100% — flag that case so the UI can render an explanatory tooltip
    # instead of silently capping the number.
    rows.each_with_index do |row, idx|
      next_row = rows[idx + 1]
      next if next_row.nil?

      row[:next_stage_id] = next_row[:id]
      row[:next_stage_name] = next_row[:name]
      row[:conversion_rate] = conversion_pct(row[:count], next_row[:count])
      row[:drop_off_count] = drop_off(row[:count], next_row[:count])
      row[:conversion_exceeds_previous] = next_row[:count] > row[:count]
    end

    rows
  end

  def stage_row(stage, count)
    {
      id: stage.id,
      name: stage.name,
      color: stage.color,
      position: stage.position,
      closed: stage.closed,
      count: count,
      next_stage_id: nil,
      next_stage_name: nil,
      conversion_rate: nil,
      drop_off_count: nil,
      conversion_exceeds_previous: false
    }
  end

  def conversion_pct(from_count, to_count)
    return nil if from_count.zero?

    ((to_count.to_f / from_count) * 100).round(2)
  end

  # Negative drop-off would be misleading (it isn't "loss" — it's an influx
  # from outside the previous stage). Clamp to zero so the UI shows "0 perdidos"
  # alongside the >100% conversion-rate flag.
  def drop_off(from_count, to_count)
    return nil if from_count.zero?

    [from_count - to_count, 0].max
  end

  def build_kpis(stages, counts)
    closed_names = stages.select(&:closed).map(&:name)
    completed = distinct_count_for(closed_names)
    won = distinct_count_for_won(closed_names)

    {
      top_count: top_open_stage_count(stages, counts),
      completed_count: completed,
      won_count: won,
      win_rate: completed.zero? ? nil : ((won.to_f / completed) * 100).round(2)
    }
  end

  def top_open_stage_count(stages, counts)
    first_open = stages.reject(&:closed).first
    return 0 if first_open.nil?

    counts[first_open.name] || 0
  end

  def distinct_count_for(stage_names)
    return 0 if stage_names.empty?

    scope = account.funnel_stage_changes.where(new_stage: stage_names)
    scope = scope.where(created_at: range) if range.present?
    scope.distinct.count(:conversation_id)
  end

  # "Won" mirrors the FunnelSummaryBuilder convention: an entry into a closed
  # stage with no loss_reason. Lost = closed + loss_reason set. No-show is
  # whichever convention the operator chose when registering the transition.
  def distinct_count_for_won(stage_names)
    return 0 if stage_names.empty?

    scope = account.funnel_stage_changes.where(new_stage: stage_names, loss_reason_id: nil)
    scope = scope.where(created_at: range) if range.present?
    scope.distinct.count(:conversation_id)
  end

  def empty_kpis
    { top_count: 0, completed_count: 0, won_count: 0, win_rate: nil }
  end
end
