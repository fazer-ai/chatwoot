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
end
