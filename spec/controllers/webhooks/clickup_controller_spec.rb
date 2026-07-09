require 'rails_helper'

RSpec.describe 'Webhooks::ClickupController', type: :request do
  let(:secret) { 'test-webhook-secret' }

  before do
    InstallationConfig.where(name: 'CLICKUP_WEBHOOK_SECRET').first_or_create!(value: secret, locked: false)
                      .update!(value: secret)
  end

  def sign(body)
    OpenSSL::HMAC.hexdigest('sha256', secret, body)
  end

  context 'without a valid signature' do
    it 'rejects the request with 401' do
      post '/webhooks/clickup',
           params: { event: 'taskStatusUpdated', task_id: 'CU_TASK_1' }.to_json,
           headers: { 'CONTENT_TYPE' => 'application/json', 'X-Signature' => 'bogus' }

      expect(response).to have_http_status(:unauthorized)
    end

    it 'still rejects when the secret is not configured (fail closed, not open)' do
      InstallationConfig.find_by(name: 'CLICKUP_WEBHOOK_SECRET').update!(value: '')

      body = { event: 'taskStatusUpdated', task_id: 'CU_TASK_1' }.to_json
      post '/webhooks/clickup',
           params: body,
           headers: { 'CONTENT_TYPE' => 'application/json', 'X-Signature' => sign(body) }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  context 'with a valid signature' do
    it 'accepts the payload and delegates to ProcessEventService' do
      body = { event: 'taskStatusUpdated', task_id: 'CU_TASK_1', history_items: [] }.to_json
      process_service = instance_double(Webhooks::Clickup::ProcessEventService, perform: nil)
      allow(Webhooks::Clickup::ProcessEventService).to receive(:new).and_return(process_service)

      post '/webhooks/clickup',
           params: body,
           headers: { 'CONTENT_TYPE' => 'application/json', 'X-Signature' => sign(body) }

      expect(response).to have_http_status(:ok)
      expect(Webhooks::Clickup::ProcessEventService).to have_received(:new)
      expect(process_service).to have_received(:perform)
    end
  end
end
