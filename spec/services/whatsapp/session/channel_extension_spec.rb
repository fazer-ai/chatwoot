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
  end

  describe 'webhook secret' do
    it 'generates one for a session provider, which is what authenticates its callback' do
      expect(build_channel('uazapi').provider_config['webhook_verify_token']).to be_present
    end

    it 'still generates one for whatsapp_cloud and baileys, and none for 360dialog' do
      expect(build_channel('baileys').provider_config['webhook_verify_token']).to be_present
      expect(build_channel('default').provider_config['webhook_verify_token']).to be_nil
    end
  end

  describe '#provider_connection_data' do
    let(:channel) { build_channel('native') }

    before do
      channel.update_provider_connection!(
        'connection' => 'close', 'error' => 'logged_out', 'pairing_code' => 'K7QP-2M4X',
        'quarantine' => { 'strikes' => 2 }, 'ban' => { 'kind' => 'temporary' }
      )
    end

    it 'translates the stored error key for administrators' do
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
