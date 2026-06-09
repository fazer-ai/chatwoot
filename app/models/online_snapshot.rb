# == Schema Information
#
# Table name: online_snapshots
#
#  id          :bigint           not null, primary key
#  snapshot_at :datetime         not null
#  account_id  :bigint           not null
#  user_id     :bigint           not null
#
# Indexes
#
#  index_online_snapshots_on_account_id                  (account_id)
#  index_online_snapshots_on_account_id_and_snapshot_at  (account_id,snapshot_at)
#  index_online_snapshots_on_user_id                     (user_id)
#  index_online_snapshots_on_user_id_and_snapshot_at     (user_id,snapshot_at)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => cascade
#
class OnlineSnapshot < ApplicationRecord
  belongs_to :account
  belongs_to :user

  # Returns the user_ids that were online in the account at (or just before)
  # the given timestamp. Looks back up to `tolerance` to find the closest
  # snapshot — captures are at 1-minute granularity so 90s tolerance gives
  # us one full window of slack.
  def self.online_at(account_id, timestamp, tolerance: 90.seconds)
    last_snapshot = where(account_id: account_id)
                    .where(snapshot_at: (timestamp - tolerance)..timestamp)
                    .order(snapshot_at: :desc)
                    .pick(:snapshot_at)
    return [] unless last_snapshot

    where(account_id: account_id, snapshot_at: last_snapshot).pluck(:user_id)
  end
end
