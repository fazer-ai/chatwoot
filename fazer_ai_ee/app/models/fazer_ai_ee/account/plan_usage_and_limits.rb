module FazerAiEe::Account::PlanUsageAndLimits
  # A negative limit is read as no allowance. Left as is, `get_captain_limits` clamps the
  # remaining quota between 0 and that negative number, which raises.
  def captain_monthly_limit
    super.transform_values { |limit| limit.to_i.negative? ? 0 : limit }
  end
end
