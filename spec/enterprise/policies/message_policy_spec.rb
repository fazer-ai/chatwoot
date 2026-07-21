require 'rails_helper'

RSpec.describe MessagePolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:agent_account_user) { agent.account_users.find_by(account: account) }
  let(:context) { { user: agent, account: account, account_user: agent_account_user } }

  let(:message) { create(:message, account: account) }

  permissions :destroy? do
    context 'when the account blocks agent message deletion' do
      before { account.update!(disable_agent_message_deletion: true) }

      it 'still allows a user with a custom role' do
        custom_role = create(:custom_role, account: account, permissions: ['conversation_manage'])
        agent_account_user.update!(custom_role: custom_role)

        expect(subject).to permit(context, message)
      end
    end
  end
end
