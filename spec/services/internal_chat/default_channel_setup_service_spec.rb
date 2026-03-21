require 'rails_helper'

describe InternalChat::DefaultChannelSetupService do
  let(:account) { create(:account) }

  describe '#perform' do
    it 'creates a default category' do
      expect do
        described_class.new(account: account).perform
      end.to change(InternalChat::Category, :count).by(1)

      category = account.internal_chat_categories.last
      expect(category.name).to eq(I18n.t('internal_chat.default_category_name', default: 'Channels'))
      expect(category.position).to eq(0)
    end

    it 'creates a default public channel' do
      expect do
        described_class.new(account: account).perform
      end.to change(InternalChat::Channel, :count).by(1)

      channel = InternalChat::Channel.last
      expect(channel.name).to eq(I18n.t('internal_chat.default_channel_name', default: 'General'))
      expect(channel).to be_channel_type_public_channel
      expect(channel.category).to eq(account.internal_chat_categories.last)
    end

    it 'adds all account users as channel members' do
      admin = create(:user, account: account, role: :administrator)
      agent = create(:user, account: account, role: :agent)

      described_class.new(account: account).perform

      channel = InternalChat::Channel.last
      expect(channel.channel_members.count).to eq(account.account_users.count)

      admin_member = channel.channel_members.find_by(user: admin)
      agent_member = channel.channel_members.find_by(user: agent)
      expect(admin_member.role).to eq('admin')
      expect(agent_member.role).to eq('member')
    end

    it 'is idempotent and does not duplicate on re-run' do
      described_class.new(account: account).perform

      expect do
        described_class.new(account: account).perform
      end.not_to change(InternalChat::Category, :count)
    end

    context 'when account has a custom locale' do
      before do
        account.update!(locale: 'fr')
      end

      it 'uses the account locale for names' do
        described_class.new(account: account).perform
        category = account.internal_chat_categories.last

        expected_name = I18n.with_locale(:fr) { I18n.t('internal_chat.default_category_name', default: 'Channels') }
        expect(category.name).to eq(expected_name)
      end
    end
  end
end
