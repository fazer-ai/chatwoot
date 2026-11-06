require 'rails_helper'

describe Whatsapp::IncomingCallService do
  let(:account) { create(:account) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account,
                              validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:from_number) { '15550001111' }
  let(:provider_call_id) { 'wacid_abc' }

  before do
    account.enable_features!('channel_voice')
    channel.provider_config = channel.provider_config.merge('source' => 'embedded_signup', 'calling_enabled' => true)
    channel.save!
  end

  def call_payload(event:, **extra)
    { calls: [{ id: provider_call_id, from: from_number, event: event, **extra }] }
  end
  describe 'inbound connect' do
    let(:sdp_offer) { "v=0\r\n...sdp..." }
    let!(:agent) { create(:user, account: account) }

    before { create(:inbox_member, inbox: inbox, user: agent) }

    # The dashboard knows a conversation by its display id: the call widget routes to it and looks it up in the
    # store by it. Conversations of another account push this one's internal ids away from its display ids.
    it 'names the conversation by its display id in voice_call.incoming' do
      other_account = create(:account)
      create_list(:conversation, 2, account: other_account)
      allow(ActionCable.server).to receive(:broadcast)

      params = call_payload(event: 'connect', session: { sdp: sdp_offer, sdp_type: 'offer' })
      described_class.new(inbox: inbox, params: params).perform

      conversation = Call.last.conversation
      expect(conversation.display_id).not_to eq(conversation.id)
      expect(ActionCable.server).to have_received(:broadcast).with(
        agent.pubsub_token,
        hash_including(event: 'voice_call.incoming', data: hash_including(conversation_id: conversation.display_id))
      )
    end
  end
end
