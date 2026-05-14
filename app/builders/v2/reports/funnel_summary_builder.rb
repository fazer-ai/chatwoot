class V2::Reports::FunnelSummaryBuilder
  include DateRangeHelper

  attr_reader :account, :params

  def initialize(account:, params:)
    @account = account
    @params = params
  end

  def build
    stages = FunnelStage.active.ordered.to_a
    return [] if stages.empty?

    stage_names = stages.map(&:name)
    in_stage_counts = fetch_in_stage_counts(stages)
    entered_counts = fetch_entered_counts(stage_names)
    avg_times = fetch_avg_times_in_stage(stage_names)
    exit_counts = fetch_exit_counts(stage_names)

    stages.map do |stage|
      build_row(stage, in_stage_counts, entered_counts, avg_times, exit_counts)
    end
  end

  private

  # Snapshot. Always NOW — date filter only narrows entry/exit/time-in-stage metrics.
  def fetch_in_stage_counts(stages)
    account.conversations
           .where(funnel_stage_id: stages.map(&:id))
           .group(:funnel_stage_id)
           .count
  end

  def fetch_entered_counts(stage_names)
    scope = account.funnel_stage_changes.where(new_stage: stage_names)
    scope = scope.where(created_at: range) if range.present?
    scope.group(:new_stage).count
  end

  # For each entry into a stage, the time spent equals
  # `next_change_at - created_at` (the entry's own created_at). When the
  # conversation is still in that stage we have no next_change_at, so use NOW —
  # otherwise a parked conversation would never count toward the average and
  # gridlocked stages would look healthier than they are.
  #
  # The period filter is applied to the ENTRY's created_at, not to the next
  # change. That matches the user-facing question "for entries that happened
  # in this period, how long did people stay?".
  AVG_TIME_SQL = <<~SQL.squish.freeze
    WITH ordered AS (
      SELECT
        new_stage,
        created_at,
        LEAD(created_at) OVER (
          PARTITION BY conversation_id
          ORDER BY created_at
        ) AS next_change_at
      FROM funnel_stage_changes
      WHERE account_id = :account_id
    )
    SELECT
      new_stage,
      AVG(EXTRACT(EPOCH FROM (COALESCE(next_change_at, NOW()) - created_at))) AS avg_seconds
    FROM ordered
    WHERE new_stage IN (:stage_names)
      AND created_at >= :since
      AND created_at < :until_exclusive
    GROUP BY new_stage
  SQL

  def fetch_avg_times_in_stage(stage_names)
    return {} if stage_names.empty? || range_endpoints.nil?

    sanitized = ActiveRecord::Base.sanitize_sql_array(
      [AVG_TIME_SQL, { account_id: account.id, stage_names: stage_names,
                       since: range_endpoints.first, until_exclusive: range_endpoints.last }]
    )
    ActiveRecord::Base.connection.select_all(sanitized).each_with_object({}) do |row, acc|
      acc[row['new_stage']] = row['avg_seconds'].to_f
    end
  end

  def fetch_exit_counts(stage_names)
    closed_names = FunnelStage.active.closed_stages.pluck(:name)
    return {} if closed_names.empty?

    base = account.funnel_stage_changes
                  .where(previous_stage: stage_names, new_stage: closed_names)
    base = base.where(created_at: range) if range.present?

    won = base.where(loss_reason_id: nil).group(:previous_stage).count
    lost = base.where.not(loss_reason_id: nil).group(:previous_stage).count

    stage_names.index_with { |name| { won: won[name] || 0, lost: lost[name] || 0 } }
  end

  def build_row(stage, in_stage_counts, entered_counts, avg_times, exit_counts)
    {
      id: stage.id,
      name: stage.name,
      color: stage.color,
      position: stage.position,
      closed: stage.closed,
      in_stage_count: in_stage_counts[stage.id] || 0,
      entered_count: entered_counts[stage.name] || 0,
      avg_time_in_stage: avg_times[stage.name] || 0,
      won_count: exit_counts.dig(stage.name, :won) || 0,
      lost_count: exit_counts.dig(stage.name, :lost) || 0
    }
  end

  # `range` (from DateRangeHelper) is a half-open range and only present when
  # both bounds were passed. For the raw window-function SQL we need explicit
  # endpoints with strict `<` upper bound to mirror the exclusive end.
  def range_endpoints
    @range_endpoints ||= range && [range.first, range.last]
  end
end
