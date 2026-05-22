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

  describe 'widget API surface' do
    let(:account) { create(:account) }
    let(:channel) { account.simulator_channels.first }

    it 'reports end_conversation? as false so the simulator UI cannot self-close' do
      expect(channel.end_conversation?).to be false
    end

    it 'reports hmac_mandatory as false (no HMAC for the simulator)' do
      expect(channel.hmac_mandatory).to be false
    end

    it 'has no hmac_token' do
      expect(channel.hmac_token).to be_nil
    end

    it 'creates a contact + contact_inbox via the same builder Channel::WebWidget uses' do
      expect { channel.create_contact_inbox(country: 'BR') }
        .to change(ContactInbox, :count).by(1)
        .and change(Contact, :count).by(1)
      contact_inbox = ContactInbox.last
      expect(contact_inbox.inbox_id).to eq(channel.inbox.id)
      expect(contact_inbox.contact.additional_attributes['country']).to eq('BR')
    end
  end
end
