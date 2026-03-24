require 'rails_helper'

describe InternalChat::DefaultChannelSetupService do
  let(:account) { create(:account) }

  describe '#perform' do
    it 'creates a default public channel' do
      described_class.new(account: account).perform

      channel = account.internal_chat_channels.find_by(
        name: I18n.t('internal_chat.default_channel_name', default: 'General')
      )
      expect(channel).to be_present
      expect(channel).to be_channel_type_public_channel
    end

    it 'adds all account users as channel members' do
      admin = create(:user, account: account, role: :administrator)
      agent = create(:user, account: account, role: :agent)

      described_class.new(account: account.reload).perform

      channel = account.internal_chat_channels.find_by(
        name: I18n.t('internal_chat.default_channel_name', default: 'General')
      )
      expect(channel.channel_members.count).to eq(account.account_users.count)

      admin_member = channel.channel_members.find_by(user: admin)
      agent_member = channel.channel_members.find_by(user: agent)
      expect(admin_member.role).to eq('admin')
      expect(agent_member.role).to eq('member')
    end

    it 'is idempotent and does not duplicate on re-run' do
      described_class.new(account: account).perform
      initial_channel_count = account.internal_chat_channels.count

      described_class.new(account: account).perform

      expect(account.internal_chat_channels.count).to eq(initial_channel_count)
    end

    context 'when account has a custom locale' do
      let(:account) { create(:account, locale: 'fr') }

      it 'uses the account locale for channel name' do
        described_class.new(account: account).perform
        expected_name = I18n.with_locale(:fr) { I18n.t('internal_chat.default_channel_name', default: 'General') }
        channel = account.internal_chat_channels.find_by(name: expected_name)
        expect(channel).to be_present
      end
    end
  end
end
