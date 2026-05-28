require 'rails_helper'

RSpec.describe CustomFilter do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }

  after do
    Current.user = nil
    Current.account = nil
  end

  describe '#set_visibility' do
    let(:custom_filter) { create(:custom_filter, account: account, user: admin) }

    context 'when user is administrator' do
      it 'sets visibility from params' do
        Current.account = account

        expect(custom_filter.visibility).to eq('personal')

        custom_filter.set_visibility(admin, { visibility: :global })
        expect(custom_filter.visibility).to eq('global')

        custom_filter.set_visibility(admin, { visibility: :personal })
        expect(custom_filter.visibility).to eq('personal')
      end
    end

    context 'when user is agent' do
      it 'forces visibility to personal regardless of params' do
        Current.account = account

        custom_filter.set_visibility(agent, { visibility: :global })
        expect(custom_filter.visibility).to eq('personal')
      end
    end

    context 'when params do not include visibility' do
      it 'keeps existing visibility for administrators' do
        Current.account = account
        custom_filter.update!(visibility: :global)

        custom_filter.set_visibility(admin, {})
        expect(custom_filter.visibility).to eq('global')
      end
    end
  end

  describe '.with_visibility' do
    let(:agent_two) { create(:user, account: account, role: :agent) }

    before do
      Current.account = account
      create(:custom_filter, account: account, user: admin, filter_type: 0, visibility: :global, name: 'admin global')
      create(:custom_filter, account: account, user: admin, filter_type: 0, visibility: :personal, name: 'admin personal')
      create(:custom_filter, account: account, user: agent, filter_type: 0, visibility: :personal, name: 'agent personal')
      create(:custom_filter, account: account, user: agent_two, filter_type: 0, visibility: :personal, name: 'agent_two personal')
      create(:custom_filter, account: account, user: admin, filter_type: 1, visibility: :global, name: 'admin contact global')
    end

    it 'returns globals plus the requesting user personal filters scoped by filter_type' do
      filters = described_class.with_visibility(agent, { filter_type: 'conversation' })
      names = filters.pluck(:name)

      expect(names).to include('admin global', 'agent personal')
      expect(names).not_to include('admin personal', 'agent_two personal', 'admin contact global')
    end

    it 'defaults to conversation when filter_type is missing' do
      filters = described_class.with_visibility(admin, {})

      expect(filters.pluck(:filter_type).uniq).to eq(['conversation'])
    end

    it 'defaults to conversation when filter_type is invalid' do
      filters = described_class.with_visibility(admin, { filter_type: 'bogus' })

      expect(filters.pluck(:filter_type).uniq).to eq(['conversation'])
    end

    it 'isolates by filter_type for contacts' do
      filters = described_class.with_visibility(agent, { filter_type: 'contact' })

      expect(filters.pluck(:name)).to eq(['admin contact global'])
    end
  end
end
