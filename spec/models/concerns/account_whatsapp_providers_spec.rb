require 'rails_helper'

RSpec.describe AccountWhatsappProviders do
  let(:account) { create(:account) }

  it 'stores the toggles in settings, keyed by name' do
    account.update!(whatsapp_native_enabled: true)

    expect(account.reload.settings['whatsapp_native_enabled']).to be(true)
  end

  it 'casts the superadmin form values, which arrive as strings' do
    account.update!(whatsapp_uazapi_disabled: '1')
    account.update!(whatsapp_native_enabled: '1')

    expect(account.reload.whatsapp_uazapi_disabled).to be(true)
    expect(account.whatsapp_native_enabled).to be(true)
  end

  # The two switches point opposite ways, and this is the example that says so. `uazapi`
  # is on offer and the switch withdraws it; `native` is being rolled out to named
  # accounts, so an account nobody has named cannot create one.
  it 'offers uazapi to an account nobody has touched, and not native' do
    expect(account.settings).not_to have_key('whatsapp_native_enabled')

    expect(account.whatsapp_session_provider_enabled?('uazapi')).to be(true)
    expect(account.whatsapp_session_provider_enabled?('native')).to be(false)
  end

  # The half that makes it a rollout rather than a wall: an account created after the
  # provider was turned on for somebody else does not join by existing.
  it 'does not offer native to an account created later' do
    account.update!(whatsapp_native_enabled: true)

    expect(create(:account).whatsapp_session_provider_enabled?('native')).to be(false)
  end

  it 'offers native to the account it was turned on for, and only that one' do
    account.update!(whatsapp_native_enabled: true)

    expect(account.whatsapp_session_provider_enabled?('native')).to be(true)
    expect(create(:account).whatsapp_session_provider_enabled?('native')).to be(false)
  end

  it 'takes uazapi away from the account it was turned off for, and leaves native alone' do
    account.update!(whatsapp_uazapi_disabled: true, whatsapp_native_enabled: true)

    expect(account.whatsapp_session_provider_enabled?('uazapi')).to be(false)
    expect(account.whatsapp_session_provider_enabled?('native')).to be(true)
  end

  # Turning it off again is what makes it reversible without a console: `false` reads the
  # same way an absent key does.
  it 'withdraws native again when the switch is turned back off' do
    account.update!(whatsapp_native_enabled: true)
    account.update!(whatsapp_native_enabled: false)

    expect(account.reload.whatsapp_session_provider_enabled?('native')).to be(false)
  end

  it 'never enables a provider this layer does not serve' do
    expect(account.whatsapp_session_provider_enabled?('baileys')).to be(false)
  end
end
