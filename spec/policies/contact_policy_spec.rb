# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ContactPolicy, type: :policy do
  subject(:contact_policy) { described_class }

  let(:account) { create(:account) }

  let(:administrator) { create(:user, :administrator, account: account) }
  let(:manager) { create(:user, account: account, role: :manager) }
  let(:agent) { create(:user, account: account) }
  let(:contact) { create(:contact) }

  let(:administrator_context) do
    { user: administrator, account: account, account_user: administrator.account_users.find_by(account: account) }
  end
  let(:manager_context) do
    { user: manager, account: account, account_user: manager.account_users.find_by(account: account) }
  end
  let(:agent_context) do
    { user: agent, account: account, account_user: agent.account_users.find_by(account: account) }
  end

  permissions :index?, :show?, :update? do
    context 'when administrator' do
      it { expect(contact_policy).to permit(administrator_context, contact) }
    end

    context 'when agent' do
      it { expect(contact_policy).to permit(agent_context, contact) }
    end
  end

  permissions :create? do
    context 'when administrator' do
      it { expect(contact_policy).to permit(administrator_context, contact) }
    end

    context 'when agent' do
      it { expect(contact_policy).to permit(agent_context, contact) }
    end
  end

  permissions :destroy? do
    context 'when administrator' do
      it { expect(contact_policy).to permit(administrator_context, contact) }
    end

    # Managers now share the "delete contact" affordance with administrators —
    # they already own contact CRUD elsewhere and the ops team asked for it.
    context 'when manager' do
      it { expect(contact_policy).to permit(manager_context, contact) }
    end

    context 'when agent' do
      it { expect(contact_policy).not_to permit(agent_context, contact) }
    end
  end
end
