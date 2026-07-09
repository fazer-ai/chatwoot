require 'rails_helper'

RSpec.describe TicketPolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:other_agent) { create(:user, account: account, role: :agent) }
  let(:manager) { create(:user, account: account, role: :administrator) }
  let(:outsider) { create(:user) }
  let(:ticket) { create(:ticket, account: account, user: agent) }

  def ctx_for(user)
    account_user = user.account_users.find_by(account_id: account.id)
    { user: user, account: account, account_user: account_user }
  end

  permissions :create? do
    it 'allows agents and administrators of the account' do
      expect(subject).to permit(ctx_for(agent), Ticket)
      expect(subject).to permit(ctx_for(manager), Ticket)
    end

    it 'denies users with no seat on the account' do
      expect(subject).not_to permit(ctx_for(outsider), Ticket)
    end
  end

  permissions :show? do
    it 'lets administrators view any ticket in their account' do
      expect(subject).to permit(ctx_for(manager), ticket)
    end

    it 'lets an agent view their own ticket' do
      expect(subject).to permit(ctx_for(agent), ticket)
    end

    it 'hides other agents tickets from an agent (no leak of existence)' do
      other_ticket = create(:ticket, account: account, user: other_agent)
      expect(subject).not_to permit(ctx_for(agent), other_ticket)
    end
  end

  describe 'Scope' do
    it 'returns everything on the account for administrators' do
      _mine = create(:ticket, account: account, user: agent)
      _theirs = create(:ticket, account: account, user: other_agent)

      resolved = described_class::Scope.new(ctx_for(manager), Ticket).resolve
      expect(resolved.count).to eq(2)
    end

    it 'narrows to the current agent for the agent role' do
      mine = create(:ticket, account: account, user: agent)
      _theirs = create(:ticket, account: account, user: other_agent)

      resolved = described_class::Scope.new(ctx_for(agent), Ticket).resolve
      expect(resolved.pluck(:id)).to eq([mine.id])
    end
  end
end
