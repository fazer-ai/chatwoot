require 'rails_helper'

RSpec.describe AccountWhatsappProviders do
  let(:account) { create(:account) }

  it 'stores the toggles in settings, keyed by name' do
    account.update!(whatsapp_native_disabled: true)

    expect(account.reload.settings['whatsapp_native_disabled']).to be(true)
  end

  it 'casts the superadmin form values, which arrive as strings' do
    account.update!(whatsapp_uazapi_disabled: '1')

    expect(account.reload.whatsapp_uazapi_disabled).to be(true)
  end

  it 'offers the session providers to an account nobody has touched' do
    expect(account.settings).not_to have_key('whatsapp_native_disabled')

    expect(account.whatsapp_session_provider_enabled?('native')).to be(true)
    expect(account.whatsapp_session_provider_enabled?('uazapi')).to be(true)
  end

  it 'takes a provider away from the account it was turned off for, and only that one' do
    account.update!(whatsapp_native_disabled: true)

    expect(account.whatsapp_session_provider_enabled?('native')).to be(false)
    expect(account.whatsapp_session_provider_enabled?('uazapi')).to be(true)
  end

  it 'never enables a provider this layer does not serve' do
    expect(account.whatsapp_session_provider_enabled?('baileys')).to be(false)
  end
end
