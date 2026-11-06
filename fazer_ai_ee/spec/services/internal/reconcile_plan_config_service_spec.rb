require 'rails_helper'

RSpec.describe Internal::ReconcilePlanConfigService do
  before { allow(ChatwootHub).to receive(:pricing_plan).and_return('community') }

  it 'resets the email branding, which reaches the customer the same way the dashboard logo does' do
    create(:installation_config, name: 'LOGO_EMAIL', value: 'https://cdn.example.com/logo.png')
    create(:installation_config, name: 'BRAND_COLOR', value: '#11D135')

    described_class.new.perform

    expect(InstallationConfig.find_by(name: 'LOGO_EMAIL').value).to eq('')
    expect(InstallationConfig.find_by(name: 'BRAND_COLOR').value).to eq('#1f93ff')
  end
end
