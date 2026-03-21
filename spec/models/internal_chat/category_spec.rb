# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InternalChat::Category do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to have_many(:channels).class_name('InternalChat::Channel').dependent(:nullify) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }

    describe 'uniqueness of name scoped to account' do
      let!(:account) { create(:account) }

      it 'does not allow duplicate names within the same account' do
        create(:internal_chat_category, account: account, name: 'General')
        duplicate = build(:internal_chat_category, account: account, name: 'General')
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:name]).to include('has already been taken')
      end

      it 'allows same name in different accounts' do
        other_account = create(:account)
        other_category = build(:internal_chat_category, account: other_account, name: 'General')
        expect(other_category).to be_valid
      end
    end
  end

  describe 'scopes' do
    describe '.ordered' do
      let(:account) { create(:account) }
      let!(:category_b) { create(:internal_chat_category, account: account, name: 'B', position: 2) }
      let!(:category_a) { create(:internal_chat_category, account: account, name: 'A', position: 1) }
      let!(:category_c) { create(:internal_chat_category, account: account, name: 'C', position: 3) }

      it 'returns categories ordered by position' do
        expect(account.internal_chat_categories.ordered.last(3)).to eq([category_a, category_b, category_c])
      end
    end
  end
end
