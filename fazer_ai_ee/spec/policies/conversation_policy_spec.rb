require 'rails_helper'

RSpec.describe ConversationPolicy, type: :policy do
  subject { described_class }

  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }

  permissions :read_receipt? do
    let(:agent_bot) { create(:agent_bot, account: account) }
    let(:agent_bot_context) { { user: agent_bot, account: account, account_user: nil } }

    # `assignee_agent_bot_id` is shared by both `ai_assignee` types, so a bot and a Captain
    # assistant can carry the same id. The bot must not inherit the assistant's assignment.
    it 'denies a bot whose id matches the Captain assistant assigned to the conversation' do
      assistant = create(:captain_assistant, account: account, id: agent_bot.id)
      conversation = create(:conversation, account: account, inbox: inbox, ai_assignee: assistant)

      expect(subject).not_to permit(agent_bot_context, conversation)
    end
  end
end
