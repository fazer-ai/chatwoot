require 'rails_helper'

describe MessageFinder do
  subject(:message_finder) { described_class.new(conversation, params) }

  let!(:account) { create(:account) }
  let!(:user) { create(:user, account: account) }
  let!(:inbox) { create(:inbox, account: account) }
  let!(:contact) { create(:contact, email: nil) }
  let!(:conversation) do
    create(:conversation, account: account, inbox: inbox, assignee: user, contact: contact)
  end

  before do
    create(:message, account: account, inbox: inbox, conversation: conversation)
    create(:message, message_type: 'activity', account: account, inbox: inbox, conversation: conversation)
    create(:message, message_type: 'activity', account: account, inbox: inbox, conversation: conversation)
    # this outgoing message creates 2 additional messages because of the email hook execution service
    create(:message, message_type: 'outgoing', account: account, inbox: inbox, conversation: conversation)
  end

  describe '#perform' do
    context 'with filter_internal_messages false' do
      let(:params) { { filter_internal_messages: false } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 6
      end
    end

    context 'with filter_internal_messages true' do
      let(:params) { { filter_internal_messages: true } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 4
      end
    end

    context 'with before attribute' do
      let!(:outgoing) { create(:message, message_type: 'outgoing', account: account, inbox: inbox, conversation: conversation) }
      let(:params) { { before: outgoing.id } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 6
      end
    end

    context 'with after attribute' do
      let(:params) { { after: conversation.messages.first.id } }

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 5
        expect(result.first.id).to be conversation.messages.second.id
        expect(result.last.message_type).to eq 'outgoing'
      end
    end

    context 'with after and before attribute' do
      let(:params) do
        {
          after: conversation.messages.first.id,
          before: conversation.messages.last.id
        }
      end

      it 'filter conversations by status' do
        result = message_finder.perform
        expect(result.count).to be 5
        expect(result.last.id).to be conversation.messages[-2].id
      end
    end
  end

  describe 'page_window with reactions' do
    # Isolated setup: skip the shared `before` block's fixtures so count assertions stay stable.
    subject(:message_finder) { described_class.new(fresh_conversation, {}) }

    let!(:fresh_conversation) { create(:conversation, account: account, inbox: inbox, contact: contact) }

    it 'does not let reactions consume the 20-item page limit' do
      # 22 non-reaction messages plus a handful of reactions interleaved.
      # Without the non-reaction-based pick, the trailing reactions could push
      # real messages off the page.
      regular_messages = []
      22.times do |i|
        regular_messages << create(:message, conversation: fresh_conversation, content: "msg #{i}")
      end
      5.times do |i|
        create(:message,
               conversation: fresh_conversation,
               content: '👍',
               content_attributes: { is_reaction: true, in_reply_to_external_id: "ext_#{i}" })
      end

      result = message_finder.perform
      non_reactions = result.reject { |m| m.content_attributes['is_reaction'] }

      # The latest non-reactions must be present even though 5 reactions came
      # after them — the page is anchored on non-reactions, not raw position.
      expect(non_reactions).to include(regular_messages.last)
      # And the page yields at least 20 non-reactions (anchor is the 20th
      # newest non-reaction, plus any newer ones). No early truncation.
      expect(non_reactions.size).to be >= 20
    end

    it 'includes reactions whose parent message is inside the visible window' do
      msg = create(:message, conversation: fresh_conversation, content: 'Hi', source_id: 'wamid.parent')
      attached_reaction = create(:message,
                                 conversation: fresh_conversation,
                                 content: '🔥',
                                 content_attributes: { is_reaction: true, in_reply_to_external_id: 'wamid.parent' })
      orphan_reaction = create(:message,
                               conversation: fresh_conversation,
                               content: '👍',
                               content_attributes: { is_reaction: true, in_reply_to_external_id: 'wamid.older.not.in.window' })

      result = message_finder.perform

      expect(result).to include(msg, attached_reaction)
      expect(result).not_to include(orphan_reaction)
    end

    it 'returns an empty scope when no non-reaction messages exist' do
      create(:message,
             conversation: fresh_conversation,
             content: '👍',
             content_attributes: { is_reaction: true, in_reply_to_external_id: 'ext_orphan' })

      expect(message_finder.perform).to be_empty
    end
  end
end
