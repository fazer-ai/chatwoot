require 'rails_helper'

RSpec.describe 'Super Admin custom branding config', type: :request do
  let(:super_admin) { create(:super_admin) }

  before do
    allow(ChatwootHub).to receive(:pricing_plan).and_return('enterprise')
    sign_in(super_admin, scope: :super_admin)
  end

  it 'saves the email logo and the brand color with the rest of the branding' do
    post '/super_admin/app_config?config=custom_branding',
         params: { app_config: { LOGO_EMAIL: 'https://cdn.example.com/logo.png', BRAND_COLOR: '#11D135', BRAND_NAME: 'Acme' } }

    expect(response).to redirect_to(super_admin_app_config_path(config: 'custom_branding'))
    expect(GlobalConfig.get_value('LOGO_EMAIL')).to eq('https://cdn.example.com/logo.png')
    expect(GlobalConfig.get_value('BRAND_COLOR')).to eq('#11D135')
    expect(GlobalConfig.get_value('BRAND_NAME')).to eq('Acme')
  end
end
