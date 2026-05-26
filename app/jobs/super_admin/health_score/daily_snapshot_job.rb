# Runs once a day at 03:00 (see config/schedule.yml). Computes the health
# score snapshot for every account so the super_admin report has a fresh
# 0-100 number per account and an N-day series for trend rendering.
# Failures on a single account are reported and skipped — the rest of the
# fleet should still get its snapshot.
class SuperAdmin::HealthScore::DailySnapshotJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform(on: Date.current)
    Account.find_each do |account|
      SuperAdmin::HealthScore::Calculator.new(account, on: on).perform
    rescue StandardError => e
      ChatwootExceptionTracker.new(e, account: account).capture_exception
    end
  end
end
