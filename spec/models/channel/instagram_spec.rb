# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join 'spec/models/concerns/reauthorizable_shared.rb'

RSpec.describe Channel::Instagram do
  let(:channel) { create(:channel_instagram) }

  it { is_expected.to validate_presence_of(:account_id) }
  it { is_expected.to validate_presence_of(:access_token) }
  it { is_expected.to validate_presence_of(:instagram_id) }
  it { is_expected.to belong_to(:account) }
  it { is_expected.to have_one(:inbox).dependent(:destroy_async) }

  it 'has a valid name' do
    expect(channel.name).to eq('Instagram')
  end

  describe 'concerns' do
    it_behaves_like 'reauthorizable'

    context 'when prompt_reauthorization!' do
      it 'calls channel notifier mail for instagram' do
        admin_mailer = double
        mailer_double = double

        expect(AdministratorNotifications::ChannelNotificationsMailer).to receive(:with).and_return(admin_mailer)
        expect(admin_mailer).to receive(:instagram_disconnect).with(channel.inbox).and_return(mailer_double)
        expect(mailer_double).to receive(:deliver_later)

        channel.prompt_reauthorization!
      end
    end
  end

  describe '.authorization_error_threshold' do
    after { GlobalConfig.clear_cache }

    it 'falls back to AUTHORIZATION_ERROR_THRESHOLD when InstallationConfig is unset' do
      InstallationConfig.where(name: 'INSTAGRAM_AUTHORIZATION_ERROR_THRESHOLD').destroy_all
      expect(described_class.authorization_error_threshold).to eq(described_class::AUTHORIZATION_ERROR_THRESHOLD)
    end

    it 'returns the InstallationConfig value when set' do
      InstallationConfig.where(name: 'INSTAGRAM_AUTHORIZATION_ERROR_THRESHOLD')
                        .first_or_create!(value: '7', locked: false)
                        .update!(value: '7')
      expect(described_class.authorization_error_threshold).to eq(7)
    end
  end

  describe '#authorization_error!' do
    # Production sees Meta return sporadic 190s on a healthy token. A
    # busy inbox (700+ msg/day) used to flip its red reauth banner the
    # first time that happened because the threshold was hard-coded to
    # 1. The bump + TTL together mean only a real burst of errors,
    # concentrated in the same window, asks for a manual reconnect.
    it 'does not trigger reauthorization until threshold is reached' do
      stub_const('Channel::Instagram::AUTHORIZATION_ERROR_THRESHOLD', 10)
      InstallationConfig.where(name: 'INSTAGRAM_AUTHORIZATION_ERROR_THRESHOLD').destroy_all

      9.times { channel.authorization_error! }
      expect(channel.reauthorization_required?).to be false

      channel.authorization_error!
      expect(channel.reauthorization_required?).to be true
    end

    it 'sets a TTL on the error counter so sparse errors do not accumulate' do
      expect(Redis::Alfred).to receive(:expire)
        .with(anything, Channel::Instagram::ERROR_COUNT_TTL.to_i)
        .at_least(:once)
        .and_call_original
      channel.authorization_error!
    end
  end
end
