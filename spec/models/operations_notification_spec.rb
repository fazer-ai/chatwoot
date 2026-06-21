require 'rails_helper'

RSpec.describe OperationsNotification do
  let(:account) { create(:account) }
  let(:other_account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:super_admin_user) { create(:user, account: account) }

  describe 'validations' do
    it 'requires title and body' do
      n = described_class.new(created_by: super_admin_user)
      expect(n).not_to be_valid
      expect(n.errors[:title]).to be_present
      expect(n.errors[:body]).to be_present
    end

    it 'requires account_id when scope_type is account' do
      n = described_class.new(title: 't', body: 'b', scope_type: :account, created_by: super_admin_user)
      expect(n).not_to be_valid
      expect(n.errors[:account_id]).to be_present
    end

    it 'does not require account_id when scope_type is all_accounts' do
      n = described_class.new(title: 't', body: 'b', scope_type: :all_accounts, created_by: super_admin_user)
      expect(n).to be_valid
    end

    it 'requires audience_value when audience_type is role' do
      n = described_class.new(title: 't', body: 'b', audience_type: :role, created_by: super_admin_user)
      expect(n).not_to be_valid
      expect(n.errors[:audience_value]).to be_present
    end
  end

  describe '.visible_for' do
    let!(:all_users_global) do
      create_notification(scope_type: :all_accounts, audience_type: :all_users)
    end
    let!(:account_only) do
      create_notification(scope_type: :account, account: account, audience_type: :all_users)
    end
    let!(:other_account_only) do
      create_notification(scope_type: :account, account: other_account, audience_type: :all_users)
    end
    let!(:admin_only) do
      create_notification(scope_type: :all_accounts, audience_type: :role, audience_value: 'administrator')
    end
    let!(:specific_user_only) do
      create_notification(scope_type: :all_accounts, audience_type: :specific_user, audience_value: user.id.to_s)
    end

    it 'shows globally-scoped notifications to every user' do
      expect(described_class.visible_for(user, account)).to include(all_users_global)
      expect(described_class.visible_for(admin, account)).to include(all_users_global)
    end

    it 'shows account-scoped notifications only to users of that account' do
      expect(described_class.visible_for(user, account)).to include(account_only)
      expect(described_class.visible_for(user, account)).not_to include(other_account_only)
    end

    it 'filters by role when audience_type is role' do
      expect(described_class.visible_for(admin, account)).to include(admin_only)
      expect(described_class.visible_for(user, account)).not_to include(admin_only)
    end

    it 'filters by user id when audience_type is specific_user' do
      expect(described_class.visible_for(user, account)).to include(specific_user_only)
      expect(described_class.visible_for(admin, account)).not_to include(specific_user_only)
    end

    it 'excludes unpublished notifications' do
      unpublished = create_notification(scope_type: :all_accounts, audience_type: :all_users, published_at: nil)
      expect(described_class.visible_for(user, account)).not_to include(unpublished)
    end

    it 'excludes expired notifications' do
      expired = create_notification(scope_type: :all_accounts, audience_type: :all_users, expires_at: 1.day.ago)
      expect(described_class.visible_for(user, account)).not_to include(expired)
    end

    it 'excludes soft-deleted notifications' do
      gone = create_notification(scope_type: :all_accounts, audience_type: :all_users)
      gone.soft_delete!
      expect(described_class.visible_for(user, account)).not_to include(gone)
    end
  end

  describe '.pending_for' do
    let!(:notification) { create_notification(scope_type: :all_accounts, audience_type: :all_users) }

    it 'lists the notification before ack' do
      expect(described_class.pending_for(user, account)).to include(notification)
    end

    it 'hides the notification after ack' do
      OperationsNotificationAck.create!(
        operations_notification: notification, user: user, account: account, acknowledged_at: Time.current
      )
      expect(described_class.pending_for(user, account)).not_to include(notification)
    end
  end

  describe 'after_create broadcast' do
    let(:other_account) { create(:account) }
    let(:other_account_agent) { create(:user, account: other_account, role: :agent) }

    before { allow(ActionCableBroadcastJob).to receive(:perform_later) }

    it 'pushes to all matching users when trigger=immediate' do
      [user, admin, other_account_agent]
      create_notification(scope_type: :all_accounts, audience_type: :all_users, trigger_kind: :immediate)

      expect(ActionCableBroadcastJob).to have_received(:perform_later) do |tokens, event, payload|
        expect(tokens).to include(user.pubsub_token, admin.pubsub_token, other_account_agent.pubsub_token)
        expect(event).to eq('operations_notification.created')
        expect(payload[:operations_notification_id]).to be_present
      end
    end

    it 'does not broadcast on on_login trigger' do
      create_notification(scope_type: :all_accounts, audience_type: :all_users, trigger_kind: :on_login)
      expect(ActionCableBroadcastJob).not_to have_received(:perform_later)
    end

    it 'restricts targets to the scoped account' do
      [user, other_account_agent]
      create_notification(scope_type: :account, account: account, audience_type: :all_users, trigger_kind: :immediate)

      expect(ActionCableBroadcastJob).to have_received(:perform_later) do |tokens, _e, _p|
        expect(tokens).to include(user.pubsub_token)
        expect(tokens).not_to include(other_account_agent.pubsub_token)
      end
    end

    it 'restricts targets by role' do
      [user, admin]
      create_notification(scope_type: :all_accounts, audience_type: :role, audience_value: 'administrator', trigger_kind: :immediate)

      expect(ActionCableBroadcastJob).to have_received(:perform_later) do |tokens, _e, _p|
        expect(tokens).to include(admin.pubsub_token)
        expect(tokens).not_to include(user.pubsub_token)
      end
    end

    it 'restricts targets to a single user' do
      [user, admin]
      create_notification(scope_type: :all_accounts, audience_type: :specific_user, audience_value: user.id.to_s, trigger_kind: :immediate)

      expect(ActionCableBroadcastJob).to have_received(:perform_later) do |tokens, _e, _p|
        expect(tokens).to eq([user.pubsub_token])
      end
    end
  end

  def create_notification(**opts)
    OperationsNotification.create!({
      title: 'Aviso',
      body: 'Body',
      severity: :info,
      trigger_kind: :immediate,
      published_at: 1.minute.ago,
      created_by: super_admin_user
    }.merge(opts))
  end
end
