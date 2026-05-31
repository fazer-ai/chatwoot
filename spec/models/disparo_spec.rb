require 'rails_helper'

RSpec.describe Disparo do
  describe 'associations' do
    it { is_expected.to belong_to(:account) }
    it { is_expected.to belong_to(:created_by).class_name('User').optional }
    it { is_expected.to have_many(:disparo_inboxes).dependent(:destroy) }
    it { is_expected.to have_many(:disparo_targets).dependent(:destroy) }
    it { is_expected.to have_many(:disparo_audience_snapshots).dependent(:destroy) }
  end

  describe 'enums' do
    it {
      expect(subject).to define_enum_for(:status).with_values(
        draft: 0, scheduled: 1, running: 2, paused: 3, completed: 4, failed: 5, cancelled: 6
      )
    }

    it { is_expected.to define_enum_for(:mode).with_values(exclusive_cloud: 0) }

    it {
      expect(subject).to define_enum_for(:conversation_status).with_values(open: 0, all: 1).with_prefix(:status)
    }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
  end

  describe 'defaults' do
    it 'defaults status to draft and mode to exclusive_cloud' do
      disparo = create(:disparo)
      expect(disparo.status).to eq('draft')
      expect(disparo.mode).to eq('exclusive_cloud')
      expect(disparo.audience_filter).to eq({})
      expect(disparo.audience_filter_dsl_version).to eq(1)
    end

    it 'defaults conversation_status to open' do
      disparo = create(:disparo)
      expect(disparo.conversation_status).to eq('open')
    end
  end
end
