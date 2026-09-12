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

  # An inbox that did not subscribe exists and receives nothing. Until now the answer was
  # never read and every failure answered `true`, so the operator saw a working inbox and
  # no messages, with a `debug` line as the only trace.
  describe 'when the webhook subscription does not go through' do
    let(:unsaved) { build(:channel_instagram) }

    it 'asks for the inbox to be reconnected when Instagram refuses' do
      allow(HTTParty).to receive(:post).and_return(instance_double(HTTParty::Response, success?: false, code: 400))

      expect(unsaved).to receive(:authorization_error!)
      expect(unsaved.subscribe).to be(false)
    end

    # Refused and not answered leave the same inbox in the same condition, and the remedy
    # is the same, so they are reported the same way.
    it 'asks for the same thing when the request does not complete at all' do
      allow(HTTParty).to receive(:post).and_raise(Net::ReadTimeout)

      expect(unsaved).to receive(:authorization_error!)
      expect(unsaved.subscribe).to be(false)
    end

    it 'says nothing when it worked' do
      allow(HTTParty).to receive(:post).and_return(instance_double(HTTParty::Response, success?: true))

      expect(unsaved).not_to receive(:authorization_error!)
      expect(unsaved.subscribe).to be(true)
    end
  end

  # Failing to unsubscribe must not stop the removal the operator asked for, but it cannot
  # be silent either: we go on receiving webhooks for an inbox that no longer exists.
  describe 'when unsubscribing does not go through' do
    it 'still lets the channel go, and says we are still subscribed there' do
      allow(HTTParty).to receive(:delete).and_raise(Net::ReadTimeout)
      allow(Rails.logger).to receive(:error)
      channel

      expect { channel.destroy! }.to change(described_class, :count).by(-1)
      expect(Rails.logger).to have_received(:error).with(/still subscribed there/)
    end
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
end
