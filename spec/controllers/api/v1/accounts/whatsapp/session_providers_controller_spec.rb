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

      it 'marks a provider creatable until the account turns it off' do
        expect(payload.find { |p| p['key'] == 'uazapi' }['creatable']).to be(true)

        account.update!(whatsapp_uazapi_disabled: true)

        expect(payload.find { |p| p['key'] == 'uazapi' }['creatable']).to be(false)
      end

      # `native` answers to two gates that point the same way and are set by different
      # people: the deployment has to serve it, and the account has to have been named.
      describe 'the two gates on native' do
        let(:native) { payload.find { |p| p['key'] == 'native' } }

        # The connector is what serves it, so an installation without one must not offer it
        # however the account is configured.
        it 'keeps it uncreatable while no connector is deployed, account opted in or not' do
          account.update!(whatsapp_native_enabled: true)

          expect(native).to include('available' => false, 'creatable' => false)
        end

        # And the half that makes a restricted first release possible: turning the connector
        # on for the deployment does not hand the provider to every account on it.
        it 'keeps it uncreatable for an account nobody named, even with a connector' do
          with_modified_env WHATSAPP_CONNECTOR_ENABLED: 'true' do
            expect(native).to include('available' => true, 'creatable' => false)
          end
        end

        it 'offers it once both are true' do
          account.update!(whatsapp_native_enabled: true)

          with_modified_env WHATSAPP_CONNECTOR_ENABLED: 'true' do
            expect(native).to include('available' => true, 'creatable' => true)
          end
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
