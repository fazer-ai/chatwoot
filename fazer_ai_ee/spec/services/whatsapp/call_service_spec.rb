require 'rails_helper'

describe Whatsapp::CallService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account,
                              validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:agent) { create(:user, account: account) }
  let(:conversation) { create(:conversation, account: account, inbox: inbox) }
  let(:call) do
    create(:call, account: account, inbox: inbox, conversation: conversation, contact: conversation.contact,
                  provider: :whatsapp, direction: :incoming, status: 'ringing', provider_call_id: 'wacid_abc')
  end
  let(:provider_service) { instance_double(Whatsapp::Providers::WhatsappCloudService) }

  before do
    channel.provider_config = channel.provider_config.merge('calling_enabled' => true)
    channel.save!
    allow(channel).to receive(:provider_service).and_return(provider_service)
    allow(inbox).to receive(:channel).and_return(channel)
    allow(call).to receive(:inbox).and_return(inbox)
    allow(ActionCable.server).to receive(:broadcast)
  end

  describe '#accept' do
    let(:sdp_answer) { "v=0\r\n...sdp..." }

    before do
      allow(provider_service).to receive(:pre_accept_call).and_return(true)
      allow(provider_service).to receive(:accept_call).and_return(true)
    end

    # Meta has already accepted by the time the claim runs, so a closed inbox must not
    # roll the acceptance back here: the call is answered and nobody is assigned.
    it 'answers without claiming the conversation while the inbox holds assignment' do
      inbox.update!(working_hours_enabled: true, restrict_assignment_to_working_hours: true)
      Current.user = agent

      travel_to(Time.utc(2026, 11, 8, 12)) do
        described_class.new(call: call, agent: agent, sdp_answer: sdp_answer).accept
      end

      expect(call.reload.status).to eq('in_progress')
      expect(conversation.reload.assignee_id).to be_nil
    ensure
      Current.reset
    end

    # The inbox can still close between the check and the save.
    it 'still records the call status when the claim itself is refused for business hours' do
      # The service reads the conversation back under the call lock, so it is another instance.
      allow_any_instance_of(Conversation).to receive(:update!).and_wrap_original do |original, attrs| # rubocop:disable RSpec/AnyInstance
        raise CustomExceptions::Conversation::OutsideWorkingHours.new({}) if attrs.key?(:assignee)

        original.call(attrs)
      end

      described_class.new(call: call, agent: agent, sdp_answer: sdp_answer).accept

      expect(call.reload.status).to eq('in_progress')
      expect(conversation.reload.assignee_id).to be_nil
      expect(conversation.additional_attributes['call_status']).to be_present
    end
  end
end
