require 'rails_helper'

RSpec.describe DisparoInbox do
  describe 'associations' do
    it { is_expected.to belong_to(:disparo) }
    it { is_expected.to belong_to(:inbox) }
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:provider).with_values(cloud: 0) }
  end

  describe 'uniqueness of inbox_id scoped to disparo' do
    let!(:disparo_inbox) { create(:disparo_inbox) }

    it 'does not allow the same inbox to be added to the same disparo twice' do
      duplicate = build(:disparo_inbox, disparo: disparo_inbox.disparo, inbox: disparo_inbox.inbox)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:inbox_id]).to include('has already been taken')
    end

    it 'allows the same inbox in a different disparo' do
      other_disparo = create(:disparo, account: disparo_inbox.disparo.account)
      other = build(:disparo_inbox, disparo: other_disparo, inbox: disparo_inbox.inbox)
      expect(other).to be_valid
    end
  end
end
