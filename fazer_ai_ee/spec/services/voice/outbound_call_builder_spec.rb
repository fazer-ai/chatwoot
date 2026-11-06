# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Voice::OutboundCallBuilder do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_twilio_sms, :with_voice, account: account, phone_number: '+15551230000') }
  let(:inbox) { channel.inbox }
  let(:user) { create(:user, account: account) }
  let(:contact) { create(:contact, account: account, phone_number: '+15550001111') }
  let(:call_sid) { 'CA1234567890abcdef' }

  before do
    allow(Twilio::VoiceWebhookSetupService).to receive(:new)
      .and_return(instance_double(Twilio::VoiceWebhookSetupService, perform: "AP#{SecureRandom.hex(8)}"))
    allow(inbox).to receive(:channel).and_return(channel)
    allow(channel).to receive(:initiate_call).and_return({ call_sid: call_sid })
  end

  describe '.perform! with a reused conversation' do
    # The dial already happened when the claim runs, so a closed inbox must not fail the
    # build and roll back the record of a call that is ringing.
    it 'places the call without claiming a reused conversation while the inbox holds assignment' do
      inbox.update!(working_hours_enabled: true, restrict_assignment_to_working_hours: true)
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact).reload
      Current.user = user

      call = travel_to(Time.utc(2026, 11, 8, 12)) do
        described_class.perform!(account: account, inbox: inbox, user: user, contact: contact, conversation: conversation)
      end

      expect(call.provider_call_id).to eq(call_sid)
      expect(conversation.reload.assignee_id).to be_nil
    ensure
      Current.reset
    end

    # Monday 17:00 closes the factory's default week while the dial is in flight.
    it 'keeps a call dialed as the inbox closes, without claiming the conversation' do
      inbox.update!(working_hours_enabled: true, restrict_assignment_to_working_hours: true)
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact).reload
      Current.user = user
      travel_to(Time.utc(2026, 11, 9, 16, 59, 59))
      allow(channel).to receive(:initiate_call) do
        travel_to(Time.utc(2026, 11, 9, 17, 0, 1))
        { call_sid: call_sid }
      end

      call = described_class.perform!(account: account, inbox: inbox, user: user, contact: contact, conversation: conversation)

      expect(call.provider_call_id).to eq(call_sid)
      expect(conversation.reload.assignee_id).to be_nil
    ensure
      travel_back
      Current.reset
    end

    # The inbox can still close between the check and the save (waiting on the row lock).
    it 'keeps the call when the claim itself is refused for business hours' do
      conversation = create(:conversation, account: account, inbox: inbox, contact: contact).reload
      allow(conversation).to receive(:update!).and_wrap_original do |original, attrs|
        raise CustomExceptions::Conversation::OutsideWorkingHours.new({}) if attrs.key?(:assignee)

        original.call(attrs)
      end

      call = described_class.perform!(account: account, inbox: inbox, user: user, contact: contact, conversation: conversation)

      expect(call.reload.provider_call_id).to eq(call_sid)
      expect(conversation.reload.assignee_id).to be_nil
    end
  end
end
