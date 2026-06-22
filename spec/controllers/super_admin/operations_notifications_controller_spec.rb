require 'rails_helper'

RSpec.describe 'Super Admin operations-notifications dashboard', type: :request do
  let(:super_admin) { create(:super_admin) }

  describe 'GET /super_admin/operations_notifications (index)' do
    # Regression: chatwoot's custom super_admin/application/index.html.erb
    # used to bypass `display_resource_name` and build the "New …" button
    # from `page.resource_name.titleize` directly, so per-dashboard
    # `resource_name` overrides (like ours that returns "notification")
    # were silently ignored and the button read "New operations notification".
    it 'renders "New notification" via the dashboard resource_name override' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/operations_notifications'
      expect(response).to have_http_status(:success)
      expect(response.body).to include('New notification')
      expect(response.body).not_to include('New operations notification')
    end
  end

  describe 'GET /super_admin/operations_notifications/new' do
    it 'renders the form' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/operations_notifications/new'
      expect(response).to have_http_status(:success)
    end

    it 'wires the scope_type select with a data target the combobox JS recognises' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/operations_notifications/new'
      # The form id is what the inline controller hooks onto.
      expect(response.body).to include('id="operations-notification-form"')
      # The select element ITSELF must carry the data attribute — not a
      # surrounding div — or the JS controller can't hook the change event.
      expect(response.body).to match(/<select[^>]*data-ops-form-target="scopeType"[^>]*name="operations_notification\[scope_type\]"/)
      # Confirm option values are the enum strings ("accounts", not "Accounts")
      # — the JS visibility check compares against the lowercase value.
      expect(response.body).to match(%r{<select[^>]*data-ops-form-target="scopeType".*?<option value="accounts">Accounts</option>}m)
      expect(response.body).to include('data-ops-form-target="accountsField"')
      expect(response.body).to include('data-ops-form-target="accountsCombobox"')
      # Inline combobox controller has to ship in the HTML — Vite isn't
      # in play on Administrate-rendered pages.
      expect(response.body).to include('mountCombobox')
      # And the <script> must sit inside <body>, before the closing tag,
      # not after </html> (which the browser silently ignores).
      body_close = response.body.index('</body>')
      script_open = response.body.index('<script')
      expect(script_open).to be < body_close
    end
  end

  describe 'GET /super_admin/operations_notifications/:id' do
    let!(:notification) do
      OperationsNotification.create!(
        title: 'Heads up',
        body: 'Body',
        created_by: super_admin,
        published_at: Time.utc(2026, 6, 22, 14, 30, 0)
      )
    end

    # Regression: the show page used to crash with `undefined method
    # 'super_admin_super_admin_path'` because Administrate's BelongsTo
    # show partial built `link_to([:super_admin, created_by])` and the
    # creator is a SuperAdmin (STI subclass of User), which doesn't have
    # its own route. We now render the creator's name as a plain string.
    it 'renders the show page' do
      sign_in(super_admin, scope: :super_admin)
      get "/super_admin/operations_notifications/#{notification.id}"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(super_admin.available_name.presence || super_admin.email)
    end

    # rubocop:disable Rails/SkipsModelValidations
    it 'renders published_at / created_at / updated_at in America/Sao_Paulo' do
      # `update_columns` is deliberate: only way to pin timestamps that
      # Rails would otherwise overwrite on save.
      notification.update_columns(
        created_at: Time.utc(2026, 6, 22, 14, 30, 0),
        updated_at: Time.utc(2026, 6, 22, 15, 0, 0)
      )
      sign_in(super_admin, scope: :super_admin)
      get "/super_admin/operations_notifications/#{notification.id}"
      # published_at + created_at == 14:30 UTC → 11:30 in São Paulo (UTC-03)
      expect(response.body).to include('2026-06-22 11:30:00')
      # updated_at == 15:00 UTC → 12:00 in São Paulo
      expect(response.body).to include('2026-06-22 12:00:00')
    end
    # rubocop:enable Rails/SkipsModelValidations
  end

  describe 'POST /super_admin/operations_notifications' do
    let(:account_one) { create(:account) }
    let(:account_two) { create(:account) }
    let(:target_user) { create(:user, account: account_one, role: :agent) }

    let(:base_params) do
      {
        operations_notification: {
          title: 'System maintenance',
          body: 'We will be performing maintenance tonight at 22:00.',
          severity: 'info',
          scope_type: 'all_accounts',
          audience_type: 'all_users',
          trigger_kind: 'immediate'
        }
      }
    end

    # Regression: the controller used to read `current_user` (always nil in
    # the super_admin Devise scope), which made `created_by` invalid and
    # bounced Administrate's form back over and over.
    it 'persists the notification with the super admin as creator' do
      sign_in(super_admin, scope: :super_admin)
      expect do
        post '/super_admin/operations_notifications', params: base_params
      end.to change(OperationsNotification, :count).by(1)
      expect(response).to have_http_status(:redirect)
      expect(OperationsNotification.last.created_by_id).to eq(super_admin.id)
    end

    it 'persists multi-account selection through repeated account_ids params' do
      sign_in(super_admin, scope: :super_admin)
      params = base_params.deep_merge(
        operations_notification: {
          scope_type: 'accounts',
          account_ids: [account_one.id.to_s, account_two.id.to_s]
        }
      )
      post '/super_admin/operations_notifications', params: params
      notification = OperationsNotification.last
      expect(notification.account_ids).to contain_exactly(account_one.id, account_two.id)
    end

    it 'persists specific_users audience with multiple audience_user_ids' do
      sign_in(super_admin, scope: :super_admin)
      target_user
      params = base_params.deep_merge(
        operations_notification: {
          scope_type: 'accounts',
          account_ids: [account_one.id.to_s],
          audience_type: 'specific_users',
          audience_user_ids: [target_user.id.to_s]
        }
      )
      post '/super_admin/operations_notifications', params: params
      notification = OperationsNotification.last
      expect(notification.audience_type).to eq('specific_users')
      expect(notification.audience_user_ids).to eq([target_user.id])
    end

    it 'redirects unauthenticated requests to login' do
      post '/super_admin/operations_notifications', params: base_params
      expect(response).to have_http_status(:redirect)
      expect(OperationsNotification.count).to eq(0)
    end
  end

  describe 'GET /super_admin/operations_notifications/:id/acks' do
    let(:account) { create(:account) }
    let(:agent) { create(:user, account: account, role: :agent) }
    let!(:notification) do
      OperationsNotification.create!(
        title: 'Heads up',
        body: 'Body',
        created_by: super_admin,
        published_at: Time.current
      )
    end

    before do
      OperationsNotificationAck.create!(
        operations_notification: notification,
        user: agent,
        account: account,
        acknowledged_at: Time.current,
        ip: '203.0.113.42',
        user_agent: 'rspec-agent/1.0'
      )
    end

    it 'lists every acknowledgement with user, account, time and IP' do
      sign_in(super_admin, scope: :super_admin)
      get "/super_admin/operations_notifications/#{notification.id}/acks"
      expect(response).to have_http_status(:success)
      expect(response.body).to include(agent.available_name.presence || agent.email)
      expect(response.body).to include(account.name)
      expect(response.body).to include('203.0.113.42')
      expect(response.body).to include('rspec-agent/1.0')
    end

    it 'renders acknowledged_at in America/Sao_Paulo, not UTC' do
      notification.operations_notification_acks.first.update!(acknowledged_at: Time.utc(2026, 6, 22, 14, 30, 0))
      sign_in(super_admin, scope: :super_admin)
      get "/super_admin/operations_notifications/#{notification.id}/acks"
      # 14:30 UTC == 11:30 in America/Sao_Paulo (UTC-03 year-round).
      expect(response.body).to include('2026-06-22 11:30:00')
      expect(response.body).not_to include('2026-06-22 14:30:00 UTC')
    end

    it 'is reachable from the index grid via a link on the ack count cell' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/operations_notifications'
      expect(response.body).to match(
        %r{<a[^>]+href="/super_admin/operations_notifications/#{notification.id}/acks"[^>]*>1</a>}
      )
    end

    # The chatwoot-customised `_collection.html.erb` titleizes the label
    # after the i18n lookup, so "Notification acks" (i18n) renders as
    # "Notification Acks" (the user-facing string requested by ops).
    it 'replaces the auto-generated "Operations Notification Acks" header' do
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/operations_notifications'
      expect(response.body).not_to include('Operations Notification Acks')
      expect(response.body).to include('Notification Acks')
    end

    it 'renders published_at and created_at columns in America/Sao_Paulo' do
      notification.update_columns(created_at: Time.utc(2026, 6, 22, 14, 30, 0)) # rubocop:disable Rails/SkipsModelValidations
      sign_in(super_admin, scope: :super_admin)
      get '/super_admin/operations_notifications'
      # 14:30 UTC → 11:30 -03 on the grid
      expect(response.body).to include('2026-06-22 11:30:00')
    end
  end

  describe 'DELETE /super_admin/operations_notifications/:id' do
    let!(:notification) do
      OperationsNotification.create!(
        title: 'Heads up',
        body: 'Body',
        created_by: super_admin,
        published_at: Time.current
      )
    end

    it 'soft-deletes the notification when authenticated' do
      sign_in(super_admin, scope: :super_admin)
      delete "/super_admin/operations_notifications/#{notification.id}"
      expect(response).to have_http_status(:redirect)
      expect(notification.reload.deleted_at).not_to be_nil
    end
  end
end
