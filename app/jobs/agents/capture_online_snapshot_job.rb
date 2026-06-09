# Snapshots which agents are 'online' in each account every minute.
# Powers the "Distribuição da IA" super admin report — by cross-referencing
# the snapshot taken closest to a team-assignment activity, we can show
# who was actually available at that exact moment (so a "stuck" attribution
# can be explained: nobody from the team was online, or some specific
# agents were online but the auto-assign missed them).
#
# Retention is 7 days, cleaned up at the start of each run.
class Agents::CaptureOnlineSnapshotJob < ApplicationJob
  queue_as :scheduled_jobs

  RETENTION = 7.days

  def perform
    cleanup_old_snapshots

    now = Time.current
    Account.find_each do |account|
      online_user_ids = fetch_online_user_ids(account.id)
      next if online_user_ids.empty?

      bulk = online_user_ids.map do |user_id|
        { account_id: account.id, user_id: user_id, snapshot_at: now }
      end
      OnlineSnapshot.insert_all(bulk) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  private

  def cleanup_old_snapshots
    OnlineSnapshot.where(snapshot_at: ...RETENTION.ago).delete_all
  end

  def fetch_online_user_ids(account_id)
    OnlineStatusTracker.get_available_users(account_id)
                       .select { |_, status| status == 'online' }
                       .keys
                       .map(&:to_i)
  end
end
