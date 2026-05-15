class V2::Reports::FunnelConversionBuilder
  include DateRangeHelper

  attr_reader :account, :params

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    all_stages = FunnelStage.active.ordered.to_a
    return { stages: [], kpis: empty_kpis } if all_stages.empty?

    # KPIs always look at the FULL set of active stages — visibility/merge
    # rules are presentation-only and shouldn't change "completed" or "won"
    # arithmetic. The chart, on the other hand, walks the display groups.
    display_groups = build_display_groups(all_stages)
    group_counts = fetch_group_counts(display_groups)
    stage_rows = build_stage_rows(display_groups, group_counts)

    { stages: stage_rows, kpis: build_kpis(all_stages) }
  end

  private

  # A "display group" is what shows up as one column in the chart. Either:
  #   - one stage with chart_visible=true and no chart_group (group of size 1)
  #   - several stages sharing the same chart_group (collapsed into one)
  # Hidden stages (chart_visible=false) never enter a group.
  def build_display_groups(stages)
    grouped, singles = partition_by_chart_group(stages.select(&:chart_visible))
    groups = singles.map { |stage| single_stage_group(stage) }
    grouped.each do |group_name, members|
      groups << merged_group(group_name, members)
    end
    groups.sort_by { |g| g[:position] }
  end

  def partition_by_chart_group(stages)
    grouped = {}
    singles = []
    stages.each do |stage|
      if stage.chart_group.present?
        grouped[stage.chart_group] ||= []
        grouped[stage.chart_group] << stage
      else
        singles << stage
      end
    end
    [grouped, singles]
  end

  def single_stage_group(stage)
    {
      key: stage.name,
      display_name: stage.chart_display_name.presence || stage.name,
      color: stage.color,
      position: stage.position,
      closed: stage.closed,
      stage_names: [stage.name],
      stage_id: stage.id
    }
  end

  # When stages collapse, the group name becomes the visible label, the first
  # member's color seeds the bar, position uses the earliest member so the
  # group lands where its first underlying stage would have. `closed` flips
  # true only if ALL members are closed — a mixed group is treated as open.
  def merged_group(group_name, members)
    {
      key: group_name,
      display_name: group_name,
      color: members.first.color,
      position: members.map(&:position).min,
      closed: members.all?(&:closed),
      stage_names: members.map(&:name),
      stage_id: nil
    }
  end

  # Counts the distinct conversation ids that entered ANY member stage of each
  # group within the period. A conversation that traversed multiple members
  # (e.g. Em Agendamento → Agendado) counts once for the merged group.
  # One DB roundtrip + Ruby-side bucketing; the dataset is small in practice.
  def fetch_group_counts(groups)
    return {} if groups.empty?

    rows = fetch_stage_change_rows(groups)
    groups.each_with_object({}) do |group, acc|
      acc[group[:key]] = distinct_conv_count_for(group, rows)
    end
  end

  def fetch_stage_change_rows(groups)
    all_names = groups.flat_map { |g| g[:stage_names] }.uniq
    scope = account.funnel_stage_changes.where(new_stage: all_names)
    scope = scope.where(created_at: range) if range.present?
    scope.distinct.pluck(:new_stage, :conversation_id)
  end

  def distinct_conv_count_for(group, rows)
    member_set = group[:stage_names].to_set
    rows.each_with_object(Set.new) do |(new_stage, conv_id), set|
      set << conv_id if member_set.include?(new_stage)
    end.size
  end

  def build_stage_rows(groups, counts)
    rows = groups.map { |group| stage_row(group, counts[group[:key]] || 0) }

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

  def stage_row(group, count)
    {
      id: group[:stage_id],
      name: group[:display_name],
      color: group[:color],
      position: group[:position],
      closed: group[:closed],
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

  # KPIs use every active stage (visible or not) so hidden closed stages like
  # No-Show / Perdido still count toward "completed".
  def build_kpis(all_stages)
    closed_names = all_stages.select(&:closed).map(&:name)
    completed = distinct_count_for(closed_names)
    won = distinct_count_for_won(closed_names)
    top_count = first_open_stage_count(all_stages)

    {
      top_count: top_count,
      completed_count: completed,
      won_count: won,
      win_rate: completed.zero? ? nil : ((won.to_f / completed) * 100).round(2)
    }
  end

  def first_open_stage_count(all_stages)
    first_open = all_stages.reject(&:closed).first
    return 0 if first_open.nil?

    distinct_count_for([first_open.name])
  end

  def distinct_count_for(stage_names)
    return 0 if stage_names.empty?

    scope = account.funnel_stage_changes.where(new_stage: stage_names)
    scope = scope.where(created_at: range) if range.present?
    scope.distinct.count(:conversation_id)
  end

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
