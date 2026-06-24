require 'rails_helper'

RSpec.describe 'IA Human Distribution Reports API', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent_user) { create(:user, account: account, name: 'Agente') }
  let(:inbox) { create(:inbox, account: account, name: 'WhatsApp Auris') }
  let(:team) { create(:team, account: account, name: 'Leger') }
  let(:ia_user) { create(:user, account: account, name: 'IA | Auris') }
  let(:reference_time) { Time.zone.local(2026, 6, 8, 14, 30) }
  let(:range_from) { (reference_time - 1.hour).to_i }
  let(:range_to) { (reference_time + 1.hour).to_i }

  let(:conv_success) { create(:conversation, account: account, inbox: inbox) }
  let(:conv_offline) { create(:conversation, account: account, inbox: inbox) }
  let(:conv_no_online) { create(:conversation, account: account, inbox: inbox) }

  before do
    create(:team_member, team: team, user: agent_user)

    # via_team — assigned agent IS in the online_user_ids set
    create(:ai_assignment_attempt,
           conversation: conv_success, account: account, team: team,
           agent_assigned: agent_user, triggered_by: ia_user,
           online_user_ids: [agent_user.id],
           created_at: reference_time)

    # assigned_via_team_offline — agent assigned but NOT in the snapshot
    create(:ai_assignment_attempt,
           conversation: conv_offline, account: account, team: team,
           agent_assigned: agent_user, triggered_by: ia_user,
           online_user_ids: [],
           created_at: reference_time + 1.minute)

    # failed_no_online — no agent assigned, empty snapshot
    create(:ai_assignment_attempt,
           conversation: conv_no_online, account: account, team: team,
           agent_assigned: nil, triggered_by: ia_user,
           online_user_ids: [],
           created_at: reference_time + 2.minutes)
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
        expect(body['totals']).to include(
          'total' => 3,
          'assigned_via_team' => 1,
          'assigned_via_team_offline' => 1,
          'failed_no_online' => 1
        )
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

      # The new audit signal the report didn't have before: an agent was
      # assigned by the IA, but nobody from the team was actually online
      # at that moment. Surfaces a likely bug in the IA assignment
      # logic — the conversation is going to a dead end.
      it 'flags via-team assignments where the assigned agent was offline' do
        get "/api/v2/accounts/#{account.id}/ia_human_distribution_reports",
            params: { from: range_from, to: range_to },
            headers: admin.create_new_auth_token

        row = response.parsed_body['rows'].find { |r| r['conversation_id'] == conv_offline.display_id }
        expect(row['status_tag']).to eq('assigned_via_team_offline')
        expect(row['status_text']).to eq('atribuído via time (agente offline)')
      end

      it 'flags failed_no_online when no one in the team had a heartbeat' do
        get "/api/v2/accounts/#{account.id}/ia_human_distribution_reports",
            params: { from: range_from, to: range_to },
            headers: admin.create_new_auth_token

        row = response.parsed_body['rows'].find { |r| r['conversation_id'] == conv_no_online.display_id }
        expect(row['status_tag']).to eq('failed_no_online')
      end

      # Regression: the report used to emit `messages.conversation_id`
      # (the global FK) which produced broken `/conversations/<id>` links
      # in the dashboard. The dashboard URL uses the per-account
      # sequential `display_id`.
      it 'returns the conversation display_id, not the global conversations.id, on every row' do
        get "/api/v2/accounts/#{account.id}/ia_human_distribution_reports",
            params: { from: range_from, to: range_to },
            headers: admin.create_new_auth_token

        rows = response.parsed_body['rows']
        expected = [conv_success, conv_offline, conv_no_online].map(&:display_id).sort
        actual = rows.map { |r| r['conversation_id'] }.sort
        expect(actual).to eq(expected)
      end

      it 'filters by inbox_id' do
        other_inbox = create(:inbox, account: account, name: 'Outra inbox')
        other_conv = create(:conversation, account: account, inbox: other_inbox)
        create(:ai_assignment_attempt,
               conversation: other_conv, account: account, team: team,
               agent_assigned: agent_user, triggered_by: ia_user,
               online_user_ids: [agent_user.id],
               created_at: reference_time + 3.minutes)

        get "/api/v2/accounts/#{account.id}/ia_human_distribution_reports",
            params: { from: range_from, to: range_to, inbox_id: other_inbox.id },
            headers: admin.create_new_auth_token

        body = response.parsed_body
        expect(body['rows'].length).to eq(1)
        expect(body['rows'].first['inbox_id']).to eq(other_inbox.id)
      end

      it 'clamps requested range to the last 7 days of retention' do
        get "/api/v2/accounts/#{account.id}/ia_human_distribution_reports",
            params: { from: 30.days.ago.to_i, to: Time.current.to_i },
            headers: admin.create_new_auth_token

        expect(response).to have_http_status(:success)
      end
    end
  end
end
