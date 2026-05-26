# V1 simplification: binary signal — at least one user with `manager` role
# on the account has `current_sign_in_at` within the last 7 days. When the
# account has no manager role at all, marks as `missing` so the weight gets
# redistributed (only ~half of small clinics have a dedicated manager).
#
# V1.5 will tighten this to "≥2 sign-ins/week for 2 consecutive weeks"
# once we have a sign-in audit log.
class SuperAdmin::HealthScore::Metrics::ManagerEngagement < SuperAdmin::HealthScore::Metrics::Base
  RECENT_WINDOW_DAYS = 7

  def compute
    managers = manager_users
    return missing(:no_manager_role) if managers.empty?

    threshold = (on - RECENT_WINDOW_DAYS).beginning_of_day
    recent = managers.where('users.current_sign_in_at >= ?', threshold)
    sub_score = recent.exists? ? 100 : 0

    present(
      sub_score,
      manager_count: managers.size,
      recent_login: sub_score == 100,
      last_sign_in_at: managers.maximum(:current_sign_in_at)&.iso8601
    )
  end

  private

  def manager_users
    User.joins(:account_users).where(account_users: { account_id: account.id, role: AccountUser.roles[:manager] })
  end
end
