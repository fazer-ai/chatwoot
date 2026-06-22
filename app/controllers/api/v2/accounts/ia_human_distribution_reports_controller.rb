class Api::V2::Accounts::IaHumanDistributionReportsController < Api::V1::Accounts::BaseController
  TZ = ActiveSupport::TimeZone['America/Sao_Paulo']
  MAX_RANGE_DAYS = 7

  before_action :check_authorization

  def index
    from = parse_unix_timestamp(params[:from])
    to = parse_unix_timestamp(params[:to])
    range = clamp_range(from, to)
    inbox_id = params[:inbox_id].presence&.to_i

    rows = build_rows(range, inbox_id)
    render json: { rows: rows, totals: tally(rows) }
  end

  private

  def check_authorization
    authorize :report, :view?
  end

  # Audit window is 7 days of retention on online_snapshots. Clamp the
  # incoming range so a user picking "Last 30 days" still gets a sane
  # report instead of a query against missing snapshot data.
  def clamp_range(from, to)
    finish = [to, Time.current].compact.min
    start = [from, finish - MAX_RANGE_DAYS.days].compact.max
    start..finish
  end

  def parse_unix_timestamp(raw)
    return nil if raw.blank?

    Time.zone.at(raw.to_i)
  end

  def build_rows(range, inbox_id)
    ctx = {
      account: Current.account,
      teams_by_name: Current.account.teams.pluck(:name, :id).to_h,
      users_by_name: User.joins(:account_users).where(account_users: { account_id: Current.account.id }).pluck(:name, :id).to_h,
      team_member_cache: {},
      inbox_cache: {}
    }

    ia_activity_messages(range, inbox_id).filter_map { |msg| build_row(msg, ctx) }
  end

  def ia_activity_messages(range, inbox_id)
    # Eager-load the conversation so we can render its `display_id` (the
    # per-account sequential id used in the dashboard URL, e.g. /28557)
    # instead of the global `messages.conversation_id` FK (which points
    # at `conversations.id`, e.g. 165581).
    scope = Message.reorder('').includes(:conversation)
                   .where(account_id: Current.account.id, message_type: :activity)
                   .where(created_at: range)
                   .where('content LIKE ?', '%por IA | Auris%')
    scope = scope.where(inbox_id: inbox_id) if inbox_id
    scope.order(:created_at)
  end

  def build_row(msg, ctx)
    parsed = parse_activity_content(msg.content.to_s)
    return nil unless parsed

    parsed = resolve_raw_target(parsed, ctx[:teams_by_name])
    team_id = parsed[:team_name] ? ctx[:teams_by_name][parsed[:team_name]] : nil
    online_user_ids = OnlineSnapshot.online_at(ctx[:account].id, msg.created_at)
    team_members = ctx[:team_member_cache][team_id] ||= (team_id ? team_member_ids(team_id) : [])
    status_text, status_tag = compute_status(parsed[:kind], team_id, team_members, online_user_ids)

    row_payload(msg, parsed, team_id, ctx, online_user_ids, team_members).merge(
      status_tag: status_tag,
      status_text: status_text
    )
  end

  # rubocop:disable Metrics/ParameterLists
  def row_payload(msg, parsed, team_id, ctx, online_user_ids, team_members)
    in_brt = msg.created_at.in_time_zone(TZ)
    {
      timestamp: in_brt.iso8601,
      date_label: in_brt.strftime('%d/%m/%Y'),
      time_label: in_brt.strftime('%H:%M:%S'),
      # Render the per-account sequential id (display_id), not the
      # global FK, so the dashboard link matches what the operator sees
      # in the conversation URL bar.
      conversation_id: msg.conversation&.display_id,
      inbox_id: msg.inbox_id,
      inbox_name: ctx[:inbox_cache][msg.inbox_id] ||= ctx[:account].inboxes.find_by(id: msg.inbox_id)&.name,
      team_id: team_id,
      team_name: parsed[:team_name],
      agent_id: parsed[:agent_name] ? ctx[:users_by_name][parsed[:agent_name]] : nil,
      agent_name: parsed[:agent_name],
      online_team_members: online_member_names(online_user_ids, team_members)
    }
  end
  # rubocop:enable Metrics/ParameterLists

  def team_member_ids(team_id)
    Team.find(team_id).members.ids
  rescue ActiveRecord::RecordNotFound
    []
  end

  def online_member_names(online_user_ids, team_members)
    User.where(id: (online_user_ids & team_members)).pluck(:id, :name)
        .map { |id, name| { id: id, name: name } }
  end

  def compute_status(kind, team_id, team_members, online_user_ids)
    case kind
    when :via_team then ['atribuído via time', 'assigned_via_team']
    when :direct   then ['assumiu a conversa', 'direct']
    when :team_only then stuck_status(team_id, team_members, online_user_ids)
    end
  end

  def stuck_status(team_id, team_members, online_user_ids)
    eligible_online = online_user_ids & team_members
    if eligible_online.any? || team_id.nil?
      ['não conseguiu atribuir', eligible_online.any? ? 'failed_with_online' : 'failed']
    else
      ['não conseguiu atribuir - ninguém ativo', 'failed_no_online']
    end
  end

  def parse_activity_content(content)
    if content =~ /\AAtribu\S+ a (.+?) via (.+?) por (?:IA \| Auris|.*Auris.*)\z/
      { kind: :via_team, agent_name: Regexp.last_match(1), team_name: Regexp.last_match(2) }
    elsif content =~ /\AAtribu\S+ a (.+?) por (?:IA \| Auris|.*Auris.*)\z/
      { kind: :raw, raw_target: Regexp.last_match(1) }
    end
  end

  def resolve_raw_target(parsed, teams_by_name)
    return parsed unless parsed[:kind] == :raw

    target = parsed[:raw_target]
    if teams_by_name.key?(target)
      { kind: :team_only, team_name: target, agent_name: nil }
    else
      { kind: :direct, agent_name: target, team_name: nil }
    end
  end

  def tally(rows)
    by_tag = rows.group_by { |r| r[:status_tag] }.transform_values(&:size)
    {
      total: rows.size,
      assigned_via_team: by_tag['assigned_via_team'] || 0,
      direct: by_tag['direct'] || 0,
      failed_with_online: by_tag['failed_with_online'] || 0,
      failed_no_online: by_tag['failed_no_online'] || 0
    }
  end
end
