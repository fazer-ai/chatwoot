require 'rails_helper'

RSpec.describe 'WhatsApp Session Providers API', type: :request do
  let(:account) { create(:account) }
  let(:url) { "/api/v1/accounts/#{account.id}/whatsapp/session_providers" }

  describe 'GET /api/v1/accounts/{account.id}/whatsapp/session_providers' do
    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        get url

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an agent' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'returns unauthorized' do
        get url, headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an administrator' do
      let(:administrator) { create(:user, account: account, role: :administrator) }

      def payload
        get url, headers: administrator.create_new_auth_token, as: :json
        response.parsed_body['payload']
      end

      it 'describes every session provider and no cloud one' do
        expect(payload.pluck('key')).to contain_exactly('native', 'uazapi', 'baileys', 'zapi')
      end

      it 'carries the form and the capabilities the dashboard renders from' do
        uazapi = payload.find { |p| p['key'] == 'uazapi' }

        expect(uazapi['fields'].pluck('name')).to include('base_url', 'token')
        expect(uazapi['fields'].find { |f| f['name'] == 'token' }).to include('required' => true, 'secret' => true)
        expect(uazapi['capabilities']).to include('reactions')
        expect(uazapi['pairing_modes']).to contain_exactly('qr', 'code')
      end

      it 'tells the picker which providers are still in beta' do
        expect(payload.select { |p| p['beta'] }.pluck('key')).to contain_exactly('native', 'uazapi')
      end

      it 'marks a provider creatable only once the account is opted in' do
        expect(payload.find { |p| p['key'] == 'uazapi' }['creatable']).to be(false)

        account.update!(whatsapp_uazapi_enabled: true)

        expect(payload.find { |p| p['key'] == 'uazapi' }['creatable']).to be(true)
      end

      # The connector is what serves `native`, so an installation without one must not
      # offer it however the account is configured.
      it 'keeps native uncreatable while no connector is deployed' do
        account.update!(whatsapp_native_enabled: true)

        expect(payload.find { |p| p['key'] == 'native' }).to include('available' => false, 'creatable' => false)

        with_modified_env WHATSAPP_CONNECTOR_ENABLED: 'true' do
          expect(payload.find { |p| p['key'] == 'native' }).to include('available' => true, 'creatable' => true)
        end
      end

      # Frozen, not withdrawn: they are what most inboxes run on today, and the
      # deprecation is what stops offering them.
      it 'keeps the legacy providers on offer' do
        legacy = payload.select { |p| p['legacy'] }

        expect(legacy.pluck('key')).to contain_exactly('baileys', 'zapi')
        expect(legacy.pluck('creatable')).to all(be(true))
      end

      it 'withdraws the legacy providers when the deprecation switch is thrown' do
        with_modified_env WHATSAPP_LEGACY_PROVIDERS_CREATABLE: 'false' do
          expect(payload.select { |p| p['legacy'] }.pluck('creatable')).to all(be(false))
        end
      end
    end
  end
end
