require 'rails_helper'

RSpec.describe Ticket do
  describe 'validations' do
    it 'requires relatar_problema' do
      ticket = build(:ticket, relatar_problema: '')
      expect(ticket).not_to be_valid
      expect(ticket.errors[:relatar_problema]).to be_present
    end

    it 'caps relatar_problema at 5000 chars so pathological pastes do not blow up the ClickUp payload' do
      ticket = build(:ticket, relatar_problema: 'x' * 5001)
      expect(ticket).not_to be_valid
    end

    it 'allows a blank comportamento_esperado since the field is optional' do
      ticket = build(:ticket, comportamento_esperado: nil)
      expect(ticket).to be_valid
    end

    it 'only accepts Message as context_type in Phase 1' do
      # After the factory's after(:build) hook attaches a message the context
      # gets normalized to a Message; force the field back to Conversation to
      # exercise the inclusion validator directly.
      ticket = build(:ticket)
      ticket.context_type = 'Conversation'
      expect(ticket).not_to be_valid
      expect(ticket.errors[:context_type]).to be_present
    end
  end

  describe 'scopes' do
    let(:account) { create(:account) }
    let(:agent) { create(:user, account: account) }
    let(:other_agent) { create(:user, account: account) }

    it 'for_user narrows to a specific agent' do
      mine = create(:ticket, account: account, user: agent)
      _theirs = create(:ticket, account: account, user: other_agent)

      expect(described_class.for_user(agent)).to eq([mine])
    end

    it 'recent_first orders newest first (drives the Meus Tickets list)' do
      older = create(:ticket, account: account, user: agent, created_at: 2.days.ago)
      newer = create(:ticket, account: account, user: agent, created_at: 1.hour.ago)

      expect(described_class.for_user(agent).recent_first).to eq([newer, older])
    end
  end

  describe '#push_event_data' do
    let(:account) { create(:account) }
    let(:agent) { create(:user, account: account, name: 'Fábio', email: 'f@auris.ia.br') }
    let(:ticket) { create(:ticket, account: account, user: agent, relatar_problema: 'x') }

    it 'exposes the fields the Meus Tickets list needs' do
      payload = ticket.push_event_data

      expect(payload[:id]).to eq(ticket.id)
      expect(payload[:account_id]).to eq(account.id)
      expect(payload[:relatar_problema]).to eq('x')
      expect(payload[:sync_status]).to eq('pending_sync')
      expect(payload[:user]).to include(id: agent.id, name: 'Fábio', email: 'f@auris.ia.br')
    end

    it 'returns user=nil when the owner has been removed' do
      ticket.update!(user: nil)
      expect(ticket.push_event_data[:user]).to be_nil
    end
  end
end
