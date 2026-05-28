# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalChat::SearchService do
  let(:account) { create(:account) }
  let(:user) { create(:user, account: account, role: :agent) }

  def perform_search(query, page: 1)
    described_class.new(
      current_user: user,
      current_account: account,
      params: { q: query, page: page }
    ).perform
  end

  describe 'minimum query length' do
    it 'returns empty results when query is shorter than 3 characters' do
      create(:internal_chat_channel, :public_channel, account: account, name: 'planning')

      result = perform_search('pl')

      expect(result[:channels]).to be_empty
      expect(result[:dms]).to be_empty
      expect(result[:messages]).to be_empty
    end
  end

  describe 'channel search' do
    before do
      create(:internal_chat_channel, :public_channel, account: account, name: 'Geral', description: 'Canal geral')
      create(:internal_chat_channel, :public_channel, account: account, name: 'Operação', description: 'equipe de operações')
      create(:internal_chat_channel, :public_channel, account: account, name: 'Unrelated', description: 'nothing here')
    end

    it 'matches by name' do
      result = perform_search('geral')
      names = result[:channels].map { |c| c[:name] }
      expect(names).to include('Geral')
    end

    it 'matches by description' do
      result = perform_search('equipe')
      names = result[:channels].map { |c| c[:name] }
      expect(names).to include('Operação')
    end

    it 'matches accented names when query is unaccented' do
      result = perform_search('operacao')
      names = result[:channels].map { |c| c[:name] }
      expect(names).to include('Operação')
    end

    it 'matches unaccented names when query is accented' do
      create(:internal_chat_channel, :public_channel, account: account, name: 'Cafe da manha')

      result = perform_search('café')
      names = result[:channels].map { |c| c[:name] }
      expect(names).to include('Cafe da manha')
    end

    it 'does not include archived channels' do
      create(:internal_chat_channel, :public_channel, :archived, account: account, name: 'Geral antigo')

      result = perform_search('geral')
      names = result[:channels].map { |c| c[:name] }
      expect(names).not_to include('Geral antigo')
    end
  end

  describe 'dm search' do
    it 'matches agent name with and without accents' do
      jose = create(:user, account: account, name: 'José da Silva', role: :agent)
      andre = create(:user, account: account, name: 'André Souza', role: :agent)
      create(:user, account: account, name: 'Mario Rossi', role: :agent)

      jose_dm = create(:internal_chat_channel, :dm, account: account)
      create(:internal_chat_channel_member, channel: jose_dm, user: user)
      create(:internal_chat_channel_member, channel: jose_dm, user: jose)

      andre_dm = create(:internal_chat_channel, :dm, account: account)
      create(:internal_chat_channel_member, channel: andre_dm, user: user)
      create(:internal_chat_channel_member, channel: andre_dm, user: andre)

      result = perform_search('jose')
      expect(result[:dms].map { |d| d[:peer][:name] }).to include('José da Silva')

      result = perform_search('André')
      expect(result[:dms].map { |d| d[:peer][:name] }).to include('André Souza')

      result = perform_search('andre')
      expect(result[:dms].map { |d| d[:peer][:name] }).to include('André Souza')
    end

    it 'returns peer avatar_url in the payload' do
      agent = create(:user, account: account, name: 'Maria', role: :agent)
      dm = create(:internal_chat_channel, :dm, account: account)
      create(:internal_chat_channel_member, channel: dm, user: user)
      create(:internal_chat_channel_member, channel: dm, user: agent)

      result = perform_search('maria')

      peer = result[:dms].find { |d| d[:peer][:user_id] == agent.id }[:peer]
      expect(peer).to have_key(:avatar_url)
    end

    it 'excludes the current user from peers' do
      other = create(:user, account: account, name: user.name, role: :agent)
      dm = create(:internal_chat_channel, :dm, account: account)
      create(:internal_chat_channel_member, channel: dm, user: user)
      create(:internal_chat_channel_member, channel: dm, user: other)

      result = perform_search(user.name[0, 3])

      peer_user_ids = result[:dms].map { |d| d[:peer][:user_id] }
      expect(peer_user_ids).not_to include(user.id)
    end
  end

  describe 'message search' do
    # Force `user` creation before the channel so the AccountUser after_create_commit
    # callback auto-joins this user to any public channels created afterward.
    before { user }

    let(:channel) { create(:internal_chat_channel, :public_channel, account: account) }

    it 'matches message content' do
      create(:internal_chat_message, account: account, channel: channel, sender: user, content: 'reunião com o cliente')

      result = perform_search('reunião')

      expect(result[:messages].map { |m| m[:content] }).to include('reunião com o cliente')
    end

    it 'matches accented content when query is unaccented' do
      create(:internal_chat_message, account: account, channel: channel, sender: user, content: 'Olá, José!')

      result = perform_search('jose')

      expect(result[:messages].map { |m| m[:content] }).to include('Olá, José!')
    end

    it 'matches unaccented content when query is accented' do
      create(:internal_chat_message, account: account, channel: channel, sender: user, content: 'jose gosta de cafe')

      result = perform_search('José')

      expect(result[:messages].map { |m| m[:content] }).to include('jose gosta de cafe')
    end

    it 'includes parent_id in the serialized result for thread replies' do
      parent = create(:internal_chat_message, account: account, channel: channel, sender: user, content: 'parent message text')
      create(:internal_chat_message, account: account, channel: channel, sender: user, content: 'reply querying foo', parent: parent)

      result = perform_search('querying')

      match = result[:messages].find { |m| m[:content] == 'reply querying foo' }
      expect(match[:parent_id]).to eq(parent.id)
    end

    it 'does not return messages from channels the user cannot access' do
      other_user = create(:user, account: account, role: :agent)
      other_channel = create(:internal_chat_channel, :private_channel, account: account, name: 'secret')
      create(:internal_chat_channel_member, channel: other_channel, user: other_user)
      create(:internal_chat_message, account: account, channel: other_channel, sender: other_user, content: 'hidden secret content')

      result = perform_search('hidden')

      expect(result[:messages]).to be_empty
    end

    it 'excludes deleted messages' do
      create(:internal_chat_message, account: account, channel: channel, sender: user, content: 'removed text', content_attributes: { deleted: true })

      result = perform_search('removed')

      expect(result[:messages]).to be_empty
    end
  end

  describe 'pagination meta' do
    it 'flags search_limited based on feature limits' do
      allow(InternalChat::Limits).to receive(:search_history_days).and_return(90)

      result = perform_search('anything')
      expect(result[:meta][:search_limited]).to be true

      allow(InternalChat::Limits).to receive(:search_history_days).and_return(nil)

      result = perform_search('anything')
      expect(result[:meta][:search_limited]).to be false
    end
  end

  describe 'search history limit' do
    before { user }

    let(:channel) { create(:internal_chat_channel, :public_channel, account: account) }

    it 'excludes messages older than the limit when one is configured' do
      allow(InternalChat::Limits).to receive(:search_history_days).and_return(90)

      old_message = create(:internal_chat_message, account: account, channel: channel, sender: user, content: 'historical reunion record')
      old_message.update_columns(created_at: 91.days.ago, updated_at: 91.days.ago) # rubocop:disable Rails/SkipsModelValidations

      recent = create(:internal_chat_message, account: account, channel: channel, sender: user, content: 'recent reunion update')

      result = perform_search('reunion')

      contents = result[:messages].map { |m| m[:content] }
      expect(contents).to include(recent.content)
      expect(contents).not_to include(old_message.content)
    end

    it 'returns messages of any age when no limit is set' do
      allow(InternalChat::Limits).to receive(:search_history_days).and_return(nil)

      old_message = create(:internal_chat_message, account: account, channel: channel, sender: user, content: 'ancient archived note')
      old_message.update_columns(created_at: 2.years.ago, updated_at: 2.years.ago) # rubocop:disable Rails/SkipsModelValidations

      result = perform_search('ancient')

      expect(result[:messages].map { |m| m[:content] }).to include(old_message.content)
    end
  end
end
