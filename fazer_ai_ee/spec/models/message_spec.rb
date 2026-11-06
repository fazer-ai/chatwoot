require 'rails_helper'

RSpec.describe Message do
  describe '#mark_pending_conversation_as_open_for_human_response' do
    let(:conversation) { create(:conversation, status: :pending) }
    let(:captain_assistant) { create(:captain_assistant, account: conversation.account) }

    before do
      create(:captain_inbox, inbox: conversation.inbox, captain_assistant: captain_assistant)
      conversation.update!(ai_assignee: captain_assistant)
    end

    # A reaction is not a reply: the conversation stays pending and with Captain.
    it 'leaves the conversation with Captain when a human only reacts' do
      create(:message, message_type: :outgoing, conversation: conversation, content: '👍',
                       content_attributes: { is_reaction: true })

      expect(conversation.reload).to have_attributes(status: 'pending', ai_assignee: captain_assistant)
    end

    it 'still opens the conversation for a human reply' do
      create(:message, message_type: :outgoing, conversation: conversation)

      expect(conversation.reload).to have_attributes(status: 'open', ai_assignee: nil)
    end
  end
end
