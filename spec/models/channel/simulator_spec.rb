# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Channel::Simulator do
  it { is_expected.to validate_presence_of(:account_id) }
  it { is_expected.to belong_to(:account) }
  it { is_expected.to have_one(:inbox).dependent(:destroy_async) }

  describe 'token generation' do
    let(:channel) { create(:account).simulator_channels.create! }

    it 'auto-generates a website_token on create' do
      expect(channel.website_token).to be_present
    end

    it 'auto-generates a pubsub_token on create' do
      expect(channel.pubsub_token).to be_present
    end

    it 'enforces a DB-level unique index on website_token' do
      account = create(:account)
      first = account.simulator_channels.first
      expect do
        account.simulator_channels.create!(website_token: first.website_token)
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  it 'reports a stable name used by the inbox UI' do
    expect(described_class.new.name).to eq('Simulator')
  end
end
