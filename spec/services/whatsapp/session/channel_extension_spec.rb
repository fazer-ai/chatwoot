require 'rails_helper'

RSpec.describe Whatsapp::Session::ChannelExtension do
  let(:account) { create(:account) }

  # The real descriptors stay unavailable until their backends ship, so the validation
  # examples stand in a descriptor that is already serving.
  def stub_descriptor(provider, backend)
    descriptor = instance_double(Whatsapp::Session::ProviderDescriptor, available?: true, backend_class: backend)
    allow(Whatsapp::Session::Registry).to receive(:descriptor).and_call_original
    allow(Whatsapp::Session::Registry).to receive(:descriptor).with(provider).and_return(descriptor)
  end

  def build_channel(provider, provider_config = {})
    create(:channel_whatsapp, account: account, provider: provider, provider_config: provider_config,
                              validate_provider_config: false, sync_templates: false)
  end

  describe '#session_provider?' do
    it 'covers only the providers this layer serves' do
      expect(build_channel('native')).to be_session_provider
      expect(build_channel('baileys')).not_to be_session_provider
    end
  end

  describe '#session_capabilities' do
    it 'answers for every whatsapp provider, not only the served ones' do
      with_modified_env WHATSAPP_GROUPS_ENABLED: 'true' do
        expect(build_channel('baileys').session_capabilities).to include('groups', 'edit')
        expect(build_channel('whatsapp_cloud').session_capabilities).to include('reactions')
        expect(build_channel('zapi').session_capabilities).not_to include('edit')
      end
    end
  end

  describe '#supports_reactions?' do
    it 'leaves the legacy and cloud providers untouched' do
      expect(build_channel('baileys').supports_reactions?).to be(true)
      expect(build_channel('zapi').supports_reactions?).to be(true)
      expect(build_channel('default').supports_reactions?).to be(false)
    end

    it 'answers from the capabilities for a session provider' do
      expect(build_channel('native').supports_reactions?).to be(true)
    end
  end

  describe 'validation' do
    it 'refuses a session provider whose backend is not deployed yet' do
      channel = build(:channel_whatsapp, account: account, provider: 'native', provider_config: {})

      expect(channel).not_to be_valid
      expect(channel.errors[:provider]).to include(I18n.t('errors.inboxes.channel.provider_unavailable'))
    end

    it 'reports the invalid config keys the backend rejected' do
      backend = Class.new(Whatsapp::Session::Backend) do
        def self.validate_config(_config) = %w[base_url token]
      end
      stub_descriptor('uazapi', backend)

      channel = build(:channel_whatsapp, account: account, provider: 'uazapi', provider_config: {})

      expect(channel).not_to be_valid
      expect(channel.errors[:provider_config].first).to include('base_url', 'token')
    end

    it 'accepts a config the backend approves' do
      backend = Class.new(Whatsapp::Session::Backend) do
        def self.validate_config(_config) = []
      end
      stub_descriptor('uazapi', backend)

      channel = build(:channel_whatsapp, account: account, provider: 'uazapi',
                                         provider_config: { 'base_url' => 'https://uazapi.test', 'token' => 'x' })

      expect(channel).to be_valid
    end

    it 'refuses a session provider the account has not opted into' do
      channel = build(:channel_whatsapp, account: account, provider: 'uazapi', session_provider_enabled: false)

      expect(channel).not_to be_valid
      expect(channel.errors[:provider]).to include(I18n.t('errors.inboxes.channel.provider_not_enabled_for_account'))
    end

    it 'refuses converting an existing inbox to a provider the account has not opted into' do
      channel = build_channel('whatsapp_cloud')

      expect do
        channel.convert_provider!(new_provider: 'uazapi', new_provider_config: { 'base_url' => 'https://uazapi.test', 'token' => 'x' })
      end.to raise_error(ActiveRecord::RecordInvalid)
      expect(channel.reload.provider).to eq('whatsapp_cloud')
    end

    it 'keeps an existing session inbox saveable after the toggle is turned back off' do
      channel = build_channel('uazapi')
      account.update!(whatsapp_uazapi_enabled: false)

      expect(channel.reload.update(provider_config: channel.provider_config.merge('mark_as_read' => false))).to be(true)
    end
  end

  describe 'connection payload' do
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'uazapi', validate_provider_config: false, sync_templates: false)
    end
    let(:state) do
      Whatsapp::Session::Model::ConnectionState.new(
        connection: 'close', error: 'logged_out', pairing_code: 'K7QP-2M4X', quarantine: { 'strikes' => 2 }
      )
    end

    # A broadcast has no single reader whose locale could be used, so the key is resolved
    # once on the way in rather than per read. Anything else hands every administrator the
    # locale of whichever job emitted the event.
    it 'stores the error already resolved, not as the key the wire carried' do
      Whatsapp::Session::ConnectionStateWriter.new(channel).apply(state)

      expect(channel.reload.provider_connection['error'])
        .to eq(I18n.t('errors.inboxes.channel.provider_connection.logged_out'))
    end

    it 'exposes the pairing details to an administrator' do
      data = channel.provider_connection_admin_data({ 'pairing_code' => 'K7QP-2M4X', 'quarantine' => { 'strikes' => 2 } })

      expect(data).to include(pairing_code: 'K7QP-2M4X', quarantine: { 'strikes' => 2 })
    end

    # The REST serializer and the Action Cable push used to build this payload
    # separately, so a live update replaced the resolved sentence with the raw key and
    # dropped the pairing details until the next refetch.
    it 'answers the same for the live push as for the inbox payload' do
      Whatsapp::Session::ConnectionStateWriter.new(channel).apply(state)
      allow(Current).to receive(:account_user).and_return(create(:account_user, account: account, role: :administrator))

      rest = channel.provider_connection_data
      push = channel.provider_connection_admin_data(channel.provider_connection)

      expect(push).to eq(rest.slice(*push.keys))
    end

    it 'leaves the legacy providers presenting exactly what they did' do
      baileys = create(:channel_whatsapp, account: account, provider: 'baileys',
                                          validate_provider_config: false, sync_templates: false)

      expect(baileys.provider_connection_admin_data({ 'error' => 'Already a sentence', 'pairing_code' => 'ignored' }))
        .to eq({ qr_data_url: nil, error: 'Already a sentence' })
    end
  end

  describe 'webhook secret' do
    it 'generates one for a session provider, which is what authenticates its callback' do
      expect(build_channel('uazapi').provider_config['webhook_verify_token']).to be_present
    end

    it 'still generates one for whatsapp_cloud and baileys, and none for 360dialog' do
      expect(build_channel('baileys').provider_config['webhook_verify_token']).to be_present
      expect(build_channel('default').provider_config['webhook_verify_token']).to be_nil
    end

    # provider_config is permitted wholesale by the inbox API and this secret is never
    # shown on the form, so an update that left the key out minted a new one while the
    # provider went on posting to the URL carrying the old: every webhook answered 401
    # until somebody reconnected the inbox.
    it 'keeps the stored one when an update leaves the key out' do
      channel = build_channel('uazapi', { 'base_url' => 'https://uazapi.test', 'token' => 'x' })
      original = channel.provider_config['webhook_verify_token']

      expect(original).to be_present

      channel.update!(provider_config: { 'base_url' => 'https://uazapi.test', 'token' => 'x' })

      expect(channel.reload.provider_config['webhook_verify_token']).to eq(original)
    end
  end

  # Destruction goes ahead whether or not the provider answered the teardown, and a
  # webhook left registered against a channel that no longer exists is a customer's
  # instance posting at a 404 for as long as it keeps trying.
  describe 'the teardown of a destroyed inbox' do
    it 'releases the webhook even when the provider will not disconnect' do
      channel = build_channel('uazapi', { 'base_url' => 'https://uazapi.test', 'token' => 'x' })
      stub_request(:post, 'https://uazapi.test/instance/disconnect').to_return(status: 500, body: '{}')
      stub_request(:post, 'https://uazapi.test/webhook').to_return(status: 200, body: '{}',
                                                                   headers: { 'Content-Type' => 'application/json' })
      allow(Resolv).to receive(:getaddresses).and_call_original
      allow(Resolv).to receive(:getaddresses).with('uazapi.test').and_return(['93.184.216.34'])

      channel.inbox.destroy!

      expect(WebMock).to have_requested(:post, 'https://uazapi.test/webhook').with(body: hash_including('enabled' => false))
    end
  end

  # A rotated token, a moved address, a second instance on the same hosted service: the
  # provider key does not change, so nothing else in the layer notices. Left alone, the
  # record goes on reporting the session the previous instance had while the new one has
  # never been told where to deliver, and the inbox reads as connected and receives nothing.
  describe 'an inbox pointed at another instance' do
    let(:channel) { build_channel('uazapi', { 'base_url' => 'https://uazapi.test', 'token' => 'first' }) }

    before do
      allow(Resolv).to receive(:getaddresses).and_call_original
      allow(Resolv).to receive(:getaddresses).with('uazapi.test').and_return(['93.184.216.34'])
      stub_request(:post, 'https://uazapi.test/webhook').to_return(status: 200, body: '{}',
                                                                   headers: { 'Content-Type' => 'application/json' })
      channel.update_provider_connection!({ 'connection' => 'open', 'phone_number' => '5541988887777' })
    end

    it 'stops reporting the session the instance it left was holding' do
      channel.update!(provider_config: channel.provider_config.merge('token' => 'second'))

      expect(channel.reload.provider_connection).to eq({})
    end

    # With the credentials it is leaving with, which are the only ones that instance takes
    # and the last chance to use them: nothing on the record names it afterwards.
    it 'withdraws the registration from the instance it left' do
      channel.update!(provider_config: channel.provider_config.merge('token' => 'second'))

      expect(WebMock).to have_requested(:post, 'https://uazapi.test/webhook')
        .with(headers: { 'token' => 'first' }, body: hash_including('enabled' => false))
    end

    it 'leaves the session alone when the save did not move the instance' do
      channel.update!(provider_config: channel.provider_config.merge('mark_as_read' => false))

      expect(channel.reload.provider_connection).to include('connection' => 'open')
      expect(WebMock).not_to have_requested(:post, 'https://uazapi.test/webhook')
    end
  end

  # The connector keys its whatsmeow store by this id, and provider_config is permitted
  # wholesale by the inbox API, so an update that left the key out used to mint a new one
  # and orphan the session the connector was still holding under the old one.
  describe 'session id' do
    it 'generates one for a session provider and none for the others' do
      expect(build_channel('native').provider_config['session_id']).to be_present
      expect(build_channel('baileys').provider_config['session_id']).to be_nil
    end

    it 'keeps the stored one when an update leaves the key out' do
      channel = build_channel('native')
      original = channel.provider_config['session_id']

      channel.update!(provider_config: { 'mark_as_read' => true })

      expect(channel.reload.provider_config['session_id']).to eq(original)
    end

    it 'refuses one handed to it by a caller' do
      channel = build_channel('native', { 'session_id' => 'a-session-that-belongs-to-someone-else' })

      expect(channel.provider_config['session_id']).not_to eq('a-session-that-belongs-to-someone-else')

      stored = channel.provider_config['session_id']
      channel.update!(provider_config: { 'session_id' => 'another-inbox-session' })
      expect(channel.reload.provider_config['session_id']).to eq(stored)
    end

    it 'refuses to store the same one on two inboxes' do
      taken = build_channel('native').provider_config['session_id']
      other = build_channel('native')

      expect { other.update_columns(provider_config: { 'session_id' => taken }) } # rubocop:disable Rails/SkipsModelValidations
        .to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe '#provider_connection_data' do
    let(:channel) { build_channel('native') }

    before do
      Whatsapp::Session::ConnectionStateWriter.new(channel).apply(
        Whatsapp::Session::Model::ConnectionState.new(
          connection: 'close', error: 'logged_out', pairing_code: 'K7QP-2M4X',
          quarantine: { 'strikes' => 2 }, ban: { 'kind' => 'temporary' }
        )
      )
    end

    it 'exposes the resolved error and the pairing details to administrators' do
      allow(Current).to receive(:account_user).and_return(create(:account_user, account: account, role: :administrator))

      data = channel.provider_connection_data

      expect(data[:error]).to eq(I18n.t('errors.inboxes.channel.provider_connection.logged_out'))
      expect(data[:pairing_code]).to eq('K7QP-2M4X')
      expect(data[:quarantine]).to eq({ 'strikes' => 2 })
      expect(data[:ban]).to eq({ 'kind' => 'temporary' })
    end

    it 'hides the pairing details from agents' do
      allow(Current).to receive(:account_user).and_return(create(:account_user, account: account, role: :agent))

      data = channel.provider_connection_data

      expect(data).to include(connection: 'close')
      expect(data).not_to have_key(:pairing_code)
      expect(data).not_to have_key(:error)
    end
  end
end
