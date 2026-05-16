# rubocop:disable Metrics/ClassLength — three orthogonal concerns (display
# groups, KPI math, loss-reason aggregation) live here on purpose; extracting
# either would mean threading account/params/range plumbing across builders
# for a marginal LOC reduction.
class V2::Reports::FunnelConversionBuilder
  include DateRangeHelper

  # KPI denominators are all "total de leads" — distinct conversations that
  # entered the first open funnel stage in the period. The other three KPIs
  # are read off specific stage identities below. Names are Auris funnel
  # canon (set/maintained by the chart-rules data migration); changing them
  # on FunnelStage means updating these constants in lockstep.
  SCHEDULING_CHART_GROUP = 'Agendamento'.freeze
  CONFIRMATION_STAGE_NAME = 'Confirmado'.freeze
  ATTENDANCE_STAGE_NAME = 'Comparecimento ( ganho )'.freeze
  NO_SHOW_STAGE_NAME = 'No-Show'.freeze

  attr_reader :account, :params

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    all_stages = FunnelStage.active.ordered.to_a
    return { stages: [], kpis: empty_kpis, loss_reasons: [] } if all_stages.empty?

    # KPIs always look at the FULL set of active stages — visibility/merge
    # rules are presentation-only and shouldn't change "completed" or "won"
    # arithmetic. The chart, on the other hand, walks the display groups.
    display_groups = build_display_groups(all_stages)
    group_counts = fetch_group_counts(display_groups)
    stage_rows = build_stage_rows(display_groups, group_counts)

    {
      stages: stage_rows,
      kpis: build_kpis(all_stages),
      loss_reasons: build_loss_reasons_breakdown
    }
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
    scope = funnel_stage_changes_scope.where(new_stage: all_names)
    scope = scope.where(created_at: range) if range.present?
    scope.distinct.pluck(:new_stage, :conversation_id)
  end

  # Single point that applies the optional inbox / label filters used by both
  # `Visão geral` and `Conversão`. Returns an ActiveRecord scope so callers
  # can chain `.where(...)` / `.group(...)` like they did before. Filters
  # default to OFF when the param is blank.
  def funnel_stage_changes_scope
    scope = account.funnel_stage_changes
    scope = scope.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    scope = scope.where(conversation_id: account.conversations.tagged_with(params[:label], on: :labels).select(:id)) if params[:label].present?
    scope
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

  # Four sales-funnel rates, all anchored on the same denominator (total
  # leads entering the funnel in the period). Hidden stages still count —
  # `chart_visible` only controls the chart bars, not the KPI math.
  def build_kpis(all_stages)
    total_leads = first_open_stage_count(all_stages)
    scheduling_count = distinct_count_for(scheduling_member_names(all_stages))
    confirmation_count = distinct_count_for([CONFIRMATION_STAGE_NAME])
    attendance_count = distinct_count_for([ATTENDANCE_STAGE_NAME])
    no_show_count = distinct_count_for([NO_SHOW_STAGE_NAME])

    {
      total_leads: total_leads,
      scheduling_count: scheduling_count,
      scheduling_rate: rate(scheduling_count, total_leads),
      confirmation_count: confirmation_count,
      confirmation_rate: rate(confirmation_count, total_leads),
      attendance_count: attendance_count,
      attendance_rate: rate(attendance_count, total_leads),
      no_show_count: no_show_count,
      no_show_rate: rate(no_show_count, total_leads)
    }
  end

  def scheduling_member_names(all_stages)
    all_stages.select { |stage| stage.chart_group == SCHEDULING_CHART_GROUP }.map(&:name)
  end

  def rate(count, total)
    return nil if total.zero?

    ((count.to_f / total) * 100).round(2)
  end

  def first_open_stage_count(all_stages)
    first_open = all_stages.reject(&:closed).first
    return 0 if first_open.nil?

    distinct_count_for([first_open.name])
  end

  def distinct_count_for(stage_names)
    return 0 if stage_names.empty?

    scope = funnel_stage_changes_scope.where(new_stage: stage_names)
    scope = scope.where(created_at: range) if range.present?
    scope.distinct.count(:conversation_id)
  end

  # Distinct conversations per loss reason in the period, sorted descending.
  # A conversation that got lost with the same reason twice still counts once
  # (mirrors how the funnel counts distinct convs per stage). Reasons with
  # zero entries in the period are omitted — the donut shouldn't render
  # empty slices.
  def build_loss_reasons_breakdown
    counts = fetch_loss_reason_counts
    return [] if counts.empty?

    total = counts.values.sum
    counts.map { |(id, name), count| loss_reason_row(id, name, count, total) }
          .sort_by { |row| -row[:count] }
  end

  def fetch_loss_reason_counts
    scope = funnel_stage_changes_scope.where.not(loss_reason_id: nil)
    scope = scope.where(created_at: range) if range.present?
    scope.joins(:loss_reason).distinct
         .group('loss_reasons.id', 'loss_reasons.name')
         .count(:conversation_id)
  end

  def loss_reason_row(id, name, count, total)
    {
      id: id,
      name: name,
      count: count,
      percentage: total.zero? ? 0 : ((count.to_f / total) * 100).round(2)
    }
  end

  def empty_kpis
    {
      total_leads: 0,
      scheduling_count: 0, scheduling_rate: nil,
      confirmation_count: 0, confirmation_rate: nil,
      attendance_count: 0, attendance_rate: nil,
      no_show_count: 0, no_show_rate: nil
    }
  end
end
# rubocop:enable Metrics/ClassLength
