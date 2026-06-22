require 'rails_helper'

RSpec.describe Agents::CaptureOnlineSnapshotJob do
  subject(:job) { described_class.new }

  let(:account) { create(:account) }
  let(:online_user) { create(:user, account: account) }
  let(:busy_user) { create(:user, account: account) }
  let(:offline_user) { create(:user, account: account) }

  describe '#perform' do
    before do
      allow(OnlineStatusTracker).to receive(:get_available_users).and_return({})
      allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return(
        online_user.id.to_s => 'online',
        busy_user.id.to_s => 'busy',
        offline_user.id.to_s => 'offline'
      )
    end

    # "Online no momento" in the IA → Humano audit treats `busy` as
    # active: those agents are logged in (heartbeat present), just
    # self-flagged as unavailable. The auto-assigner can still target
    # them, so they belong in the snapshot.
    it 'inserts users that are online or busy, but skips offline' do
      expect { job.perform }.to change(OnlineSnapshot.where(account: account), :count).by(2)

      ids = OnlineSnapshot.where(account: account).pluck(:user_id)
      expect(ids).to contain_exactly(online_user.id, busy_user.id)
    end

    it 'stamps all snapshots in the same run with the same timestamp' do
      another_account = create(:account)
      another_user = create(:user, account: another_account)
      allow(OnlineStatusTracker).to receive(:get_available_users).with(another_account.id).and_return(
        another_user.id.to_s => 'online'
      )

      job.perform

      timestamps = OnlineSnapshot.distinct.pluck(:snapshot_at)
      expect(timestamps.size).to eq(1)
    end

    it 'does not write anything for accounts with no online agents' do
      allow(OnlineStatusTracker).to receive(:get_available_users).with(account.id).and_return({})

      expect { job.perform }.not_to change(OnlineSnapshot, :count)
    end

    it 'deletes snapshots older than the retention window' do
      stale = create(:online_snapshot, account: account, user: online_user,
                                       snapshot_at: 8.days.ago)
      fresh = create(:online_snapshot, account: account, user: online_user,
                                       snapshot_at: 1.hour.ago)

      job.perform

      expect(OnlineSnapshot.exists?(stale.id)).to be false
      expect(OnlineSnapshot.exists?(fresh.id)).to be true
    end
  end
end
