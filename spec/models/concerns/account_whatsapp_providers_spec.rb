require 'rails_helper'

RSpec.describe AccountWhatsappProviders do
  let(:account) { create(:account) }

  it 'stores the rollout toggles in settings, keyed by name' do
    account.update!(whatsapp_native_enabled: true)

    expect(account.reload.settings['whatsapp_native_enabled']).to be(true)
  end

  it 'casts the superadmin form values, which arrive as strings' do
    account.update!(whatsapp_uazapi_enabled: '1')

    expect(account.reload.whatsapp_uazapi_enabled).to be(true)
  end

  it 'keeps the session providers opt-in during the rollout' do
    expect(account.whatsapp_session_provider_enabled?('native')).to be(false)

    account.update!(whatsapp_native_enabled: true)

    expect(account.whatsapp_session_provider_enabled?('native')).to be(true)
    expect(account.whatsapp_session_provider_enabled?('uazapi')).to be(false)
  end

  it 'never enables a provider this layer does not serve' do
    expect(account.whatsapp_session_provider_enabled?('baileys')).to be(false)
  end
end
