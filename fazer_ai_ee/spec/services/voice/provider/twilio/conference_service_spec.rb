require 'rails_helper'

describe Voice::Provider::Twilio::ConferenceService do
  let(:account) { create(:account) }
  let(:channel) { create(:channel_twilio_sms, :with_voice, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: channel.inbox) }
  let(:call) do
    create(
      :call,
      account: account,
      inbox: channel.inbox,
      conversation: conversation,
      contact: conversation.contact
    )
  end
  let(:twilio_client) { instance_double(Twilio::REST::Client) }
  let(:service) { described_class.new(call: call) }
  let(:webhook_service) { instance_double(Twilio::VoiceWebhookSetupService, perform: true) }

  before do
    allow(Twilio::VoiceWebhookSetupService).to receive(:new).and_return(webhook_service)
    allow(Twilio::REST::Client).to receive(:new).and_return(twilio_client)
  end

  describe '#mark_agent_joined' do
    it 'leaves the conversation unassigned while the inbox holds assignment' do
      agent = create(:user, account: account, role: :agent)
      channel.inbox.update!(working_hours_enabled: true, restrict_assignment_to_working_hours: true)
      Current.user = agent

      travel_to(Time.utc(2026, 11, 8, 12)) { service.mark_agent_joined(user: agent) }

      expect(call.reload.accepted_by_agent_id).to eq(agent.id)
      expect(conversation.reload.assignee).to be_nil
    ensure
      Current.reset
    end

    it 'joins the agent when the claim itself is refused for business hours' do
      agent = create(:user, account: account, role: :agent)
      allow(Conversations::AssignmentService).to receive(:new)
        .and_return(instance_double(Conversations::AssignmentService, perform: nil).tap do |service|
          allow(service).to receive(:perform).and_raise(CustomExceptions::Conversation::OutsideWorkingHours.new({}))
        end)

      expect { service.mark_agent_joined(user: agent) }.not_to raise_error

      expect(call.reload.accepted_by_agent_id).to eq(agent.id)
      expect(conversation.reload.assignee).to be_nil
    end
  end
end
