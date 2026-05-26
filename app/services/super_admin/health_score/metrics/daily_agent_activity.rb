# % of business days (Mon-Fri) in the last 14d with at least one outgoing
# message sent by a User (agent/manager/admin) on the account. "Active" =
# the team actually engaged with conversations that day, not just opened
# the dashboard.
class SuperAdmin::HealthScore::Metrics::DailyAgentActivity < SuperAdmin::HealthScore::Metrics::Base
  WINDOW_DAYS = 14

  def compute
    days = business_days
    return present(0, active_days: 0, business_days: days.size, active_dates: []) if days.empty?

    active_dates = days.select { |day| any_outgoing_user_message?(day) }
    pct = active_dates.size.to_f / days.size
    sub_score = (pct * 100).round

    present(sub_score, active_days: active_dates.size, business_days: days.size, active_dates: active_dates.map(&:iso8601))
  end

  private

  def business_days
    ((on - WINDOW_DAYS + 1)..on).reject { |d| d.saturday? || d.sunday? }
  end

  def any_outgoing_user_message?(day)
    Message.exists?(account_id: account.id,
                    message_type: :outgoing,
                    sender_type: 'User',
                    created_at: day.all_day)
  end
end
