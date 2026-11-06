require 'rails_helper'

RSpec.describe 'WhatsApp Calls API', type: :request do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', account: account,
                              validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { channel.inbox }
  let(:provider_service) { instance_double(Whatsapp::Providers::WhatsappCloudService) }
  let(:contact) { create(:contact, account: account, phone_number: '+15551234567') }
  let!(:contact_inbox) { create(:contact_inbox, contact: contact, inbox: inbox, source_id: '15551234567') }
  let(:initiate_conversation) do
    create(:conversation, account: account, inbox: inbox, contact: contact, contact_inbox: contact_inbox)
  end

  before do
    account.enable_features!('channel_voice')
    channel.provider_config = channel.provider_config.merge('source' => 'embedded_signup', 'calling_enabled' => true)
    channel.save!
    create(:inbox_member, user: agent, inbox: inbox)
    allow(Whatsapp::Providers::WhatsappCloudService).to receive(:new).and_return(provider_service)
  end

  describe 'POST /api/v1/accounts/:account_id/whatsapp_calls/initiate' do
    # The dial already happened by the time the claim runs, so a closed inbox must not
    # turn it into a refusal: the call goes through and the conversation stays unassigned.
    it 'places the call without claiming the conversation while the inbox holds assignment' do
      inbox.update!(working_hours_enabled: true, restrict_assignment_to_working_hours: true)
      initiate_conversation
      allow(provider_service).to receive(:initiate_call).and_return({ 'calls' => [{ 'id' => 'wacid_closed' }] })

      travel_to(Time.utc(2026, 11, 8, 12)) do
        post "/api/v1/accounts/#{account.id}/whatsapp_calls/initiate",
             params: { conversation_id: initiate_conversation.display_id, sdp_offer: 'sdp_offer' },
             headers: agent.create_new_auth_token
      end

      expect(response).to have_http_status(:ok)
      expect(Call.find_by(provider_call_id: 'wacid_closed')).to be_present
      expect(initiate_conversation.reload.assignee_id).to be_nil
    end

    # Monday 17:00 closes the factory's default week while the dial is in flight.
    it 'keeps a call dialed as the inbox closes, without claiming the conversation' do
      inbox.update!(working_hours_enabled: true, restrict_assignment_to_working_hours: true)
      initiate_conversation
      travel_to(Time.utc(2026, 11, 9, 16, 59, 59))
      allow(provider_service).to receive(:initiate_call) do
        travel_to(Time.utc(2026, 11, 9, 17, 0, 1))
        { 'calls' => [{ 'id' => 'wacid_closing' }] }
      end

      post "/api/v1/accounts/#{account.id}/whatsapp_calls/initiate",
           params: { conversation_id: initiate_conversation.display_id, sdp_offer: 'sdp_offer' },
           headers: agent.create_new_auth_token

      expect(response).to have_http_status(:ok)
      expect(Call.find_by(provider_call_id: 'wacid_closing')).to be_present
      expect(initiate_conversation.reload.assignee_id).to be_nil
    ensure
      travel_back
    end
  end
end
