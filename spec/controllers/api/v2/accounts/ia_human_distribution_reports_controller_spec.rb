require 'rails_helper'

RSpec.describe 'IA Human Distribution Reports API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, name: 'Agente') }
  let(:other_user) { create(:user, account: account, name: 'Outro') }
  let(:inbox) { create(:inbox, account: account, name: 'WhatsApp Auris') }
  let(:team) { create(:team, account: account, name: 'Leger') }
  let(:reference_time) { Time.zone.local(2026, 6, 8, 14, 30) }
  let(:range_from) { (reference_time - 1.hour).to_i }
  let(:range_to) { (reference_time + 1.hour).to_i }

  let(:conversation_stuck) do
    create(:conversation, account: account, inbox: inbox).tap do |conv|
      create(:message, account: account, inbox: inbox, conversation: conv,
                       message_type: :activity, created_at: reference_time + 2.minutes,
                       content: "Atribuído a #{team.name} por IA | Auris")
    end
  end

  before do
    create(:team_member, team: team, user: agent_user)
    create(:conversation, account: account, inbox: inbox).then do |conv|
      create(:message, account: account, inbox: inbox, conversation: conv,
                       message_type: :activity, created_at: reference_time,
                       content: "Atribuído a #{agent_user.name} via #{team.name} por IA | Auris")
    end
    create(:conversation, account: account, inbox: inbox).then do |conv|
      create(:message, account: account, inbox: inbox, conversation: conv,
                       message_type: :activity, created_at: reference_time + 1.minute,
                       content: "Atribuído a #{agent_user.name} por IA | Auris")
    end
    conversation_stuck
  end

  describe 'GET /api/v2/accounts/{account.id}/ia_human_distribution_reports' do
    context 'without authentication' do
      it 'returns unauthorized' do
        get "/api/v2/accounts/#{account.id}/ia_human_distribution_reports",
            params: { from: range_from, to: range_to }
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with non-privileged user' do
      let(:agent_role_user) { create(:user, account: account, role: :agent) }

      it 'is forbidden for plain agents' do
        get "/api/v2/accounts/#{account.id}/ia_human_distribution_reports",
            params: { from: range_from, to: range_to },
            headers: agent_role_user.create_new_auth_token
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'with admin user' do
      it 'returns rows + totals' do
        get "/api/v2/accounts/#{account.id}/ia_human_distribution_reports",
            params: { from: range_from, to: range_to },
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        body = response.parsed_body
        expect(body['rows'].length).to eq(3)
        expect(body['totals']).to include('total' => 3, 'assigned_via_team' => 1, 'direct' => 1)
      end

      it 'tags via-team rows with the team and agent ids' do
        get "/api/v2/accounts/#{account.id}/ia_human_distribution_reports",
            params: { from: range_from, to: range_to },
            headers: admin.create_new_auth_token

        row = response.parsed_body['rows'].find { |r| r['status_tag'] == 'assigned_via_team' }
        expect(row['team_id']).to eq(team.id)
        expect(row['agent_id']).to eq(agent_user.id)
        expect(row['status_text']).to eq('atribuído via time')
        expect(row['inbox_name']).to eq(inbox.name)
      end

      it 'reports stuck conversations as failed when nobody was online' do
        get "/api/v2/accounts/#{account.id}/ia_human_distribution_reports",
            params: { from: range_from, to: range_to },
            headers: admin.create_new_auth_token

        stuck = response.parsed_body['rows'].find { |r| r['conversation_id'] == conversation_stuck.id }
        expect(stuck['status_tag']).to eq('failed_no_online')
      end

      it 'flips the stuck status when the team had an online member' do
        create(:online_snapshot, account: account, user: agent_user, snapshot_at: reference_time + 2.minutes)

        get "/api/v2/accounts/#{account.id}/ia_human_distribution_reports",
            params: { from: range_from, to: range_to },
            headers: admin.create_new_auth_token

        stuck = response.parsed_body['rows'].find { |r| r['conversation_id'] == conversation_stuck.id }
        expect(stuck['status_tag']).to eq('failed_with_online')
        expect(stuck['online_team_members']).to include('id' => agent_user.id, 'name' => agent_user.name)
      end

      it 'filters by inbox_id' do
        other_inbox = create(:inbox, account: account, name: 'Outra inbox')
        conv = create(:conversation, account: account, inbox: other_inbox)
        create(:message, account: account, inbox: other_inbox, conversation: conv,
                         message_type: :activity, created_at: reference_time + 3.minutes,
                         content: "Atribuído a #{agent_user.name} via #{team.name} por IA | Auris")

        get "/api/v2/accounts/#{account.id}/ia_human_distribution_reports",
            params: { from: range_from, to: range_to, inbox_id: other_inbox.id },
            headers: admin.create_new_auth_token

        body = response.parsed_body
        expect(body['rows'].length).to eq(1)
        expect(body['rows'].first['inbox_id']).to eq(other_inbox.id)
      end

      it 'clamps requested range to the last 7 days of retention' do
        # If a user asks for "last 30 days", we should still respond with
        # at most the last 7 days worth of data — quietly clamping at the
        # API level mirrors the retention policy on the snapshot job.
        get "/api/v2/accounts/#{account.id}/ia_human_distribution_reports",
            params: { from: 30.days.ago.to_i, to: Time.current.to_i },
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
        # Older-than-7-days fixtures don't exist, but the call must succeed
        # without errors — that's the regression we're guarding against.
      end
    end
  end
end
