require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::OperationsNotifications', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_user) { create(:user, account: account, role: :agent) }
  let(:creator) { create(:user, account: account) }

  let!(:notification) do
    OperationsNotification.create!(
      title: 'Manutenção programada',
      body: 'Vamos derrubar o sistema 5 minutos',
      severity: :info,
      scope_type: :all_accounts,
      audience_type: :all_users,
      trigger_kind: :on_login,
      published_at: 1.minute.ago,
      created_by: creator
    )
  end

  describe 'GET /pending' do
    it 'returns the notification when not acked yet' do
      get pending_api_v1_account_operations_notifications_path(account.id),
          headers: agent.create_new_auth_token
      expect(response).to have_http_status(:ok)
      payload = response.parsed_body.dig('data', 'payload')
      expect(payload.length).to eq(1)
      expect(payload.first['title']).to eq('Manutenção programada')
      expect(payload.first['acknowledged_at']).to be_nil
    end

    it 'hides the notification after ack' do
      OperationsNotificationAck.create!(
        operations_notification: notification, user: agent, account: account, acknowledged_at: Time.current
      )
      get pending_api_v1_account_operations_notifications_path(account.id),
          headers: agent.create_new_auth_token
      payload = response.parsed_body.dig('data', 'payload')
      expect(payload).to be_empty
    end
  end

  describe 'GET /' do
    it 'returns the notification with acknowledged_at populated when acked' do
      OperationsNotificationAck.create!(
        operations_notification: notification, user: agent, account: account, acknowledged_at: Time.current
      )
      get api_v1_account_operations_notifications_path(account.id),
          headers: agent.create_new_auth_token
      payload = response.parsed_body.dig('data', 'payload')
      expect(payload.length).to eq(1)
      expect(payload.first['acknowledged_at']).not_to be_nil
    end

    it 'does not leak acks from other users' do
      OperationsNotificationAck.create!(
        operations_notification: notification, user: other_user, account: account, acknowledged_at: Time.current
      )
      get api_v1_account_operations_notifications_path(account.id),
          headers: agent.create_new_auth_token
      payload = response.parsed_body.dig('data', 'payload')
      expect(payload.first['acknowledged_at']).to be_nil
    end
  end

  describe 'POST /:id/acknowledge' do
    it 'creates an ack with ip and user_agent captured' do
      post acknowledge_api_v1_account_operations_notification_path(account.id, notification.id),
           headers: agent.create_new_auth_token.merge('HTTP_USER_AGENT' => 'rspec-agent')
      expect(response).to have_http_status(:ok)
      ack = OperationsNotificationAck.find_by!(operations_notification: notification, user: agent)
      expect(ack.account_id).to eq(account.id)
      expect(ack.user_agent).to eq('rspec-agent')
      expect(ack.ip).to be_present
    end

    it 'is idempotent on repeated calls' do
      2.times do
        post acknowledge_api_v1_account_operations_notification_path(account.id, notification.id),
             headers: agent.create_new_auth_token
      end
      expect(OperationsNotificationAck.where(operations_notification: notification, user: agent).count).to eq(1)
    end
  end
end
