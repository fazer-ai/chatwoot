require 'rails_helper'

RSpec.describe AiAssignmentAttempt do
  describe '.ia_driven_user?' do
    it 'matches users whose name contains "Auris" (case-insensitive)' do
      expect(described_class.ia_driven_user?(build_stubbed(:user, name: 'IA | Auris'))).to be true
      expect(described_class.ia_driven_user?(build_stubbed(:user, name: 'auris bot'))).to be true
    end

    it 'rejects regular users' do
      expect(described_class.ia_driven_user?(build_stubbed(:user, name: 'Maria'))).to be false
    end

    it 'rejects nil' do
      expect(described_class.ia_driven_user?(nil)).to be false
    end
  end

  describe '#status_tag' do
    let(:agent) { create(:user) }
    let(:attempt) do
      build_stubbed(:ai_assignment_attempt,
                    agent_assigned_id: agent_assigned_id,
                    online_user_ids: online_user_ids)
    end

    context 'when agent assigned AND agent is in online set' do
      let(:agent_assigned_id) { agent.id }
      let(:online_user_ids) { [agent.id, 999] }

      it { expect(attempt.status_tag).to eq 'assigned_via_team' }
    end

    # Surfaces the suspicious case: IA assigned someone who was offline.
    context 'when agent assigned but NOT in online set' do
      let(:agent_assigned_id) { agent.id }
      let(:online_user_ids) { [] }

      it { expect(attempt.status_tag).to eq 'assigned_via_team_offline' }
    end

    context 'when no agent assigned and nobody online' do
      let(:agent_assigned_id) { nil }
      let(:online_user_ids) { [] }

      it { expect(attempt.status_tag).to eq 'failed_no_online' }
    end

    context 'when no agent assigned but some team members were online' do
      let(:agent_assigned_id) { nil }
      let(:online_user_ids) { [agent.id] }

      it { expect(attempt.status_tag).to eq 'failed_with_online' }
    end
  end
end
