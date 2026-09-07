# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Brand do
  let(:account) { create(:account) }

  def install(values)
    values.each { |name, value| InstallationConfig.where(name: name).first_or_initialize.update!(value: value) }
    GlobalConfig.clear_cache
  end

  before do
    install(
      'BRAND_NAME' => 'Chatwoot',
      'BRAND_URL' => 'https://www.chatwoot.com',
      'BRAND_COLOR' => '#1F93FF',
      'LOGO' => '/brand-assets/logo.svg',
      'LOGO_EMAIL' => ''
    )
  end

  context 'without an account' do
    it 'is the installation brand' do
      brand = described_class.for

      expect(brand.name).to eq 'Chatwoot'
      expect(brand.url).to eq 'https://www.chatwoot.com'
      expect(brand.color).to eq '#1F93FF'
    end
  end

  context 'when the account has not enabled branded email templates' do
    before { account.update!(brand_name: 'Guichê Web', brand_color: '#11D135') }

    it 'ignores what the account configured' do
      brand = described_class.for(account: account)

      expect(brand.name).to eq 'Chatwoot'
      expect(brand.color).to eq '#1F93FF'
    end
  end

  context 'when the account has enabled branded email templates' do
    before { account.enable_features!('branded_email_templates') }

    it 'overrides field by field, leaving the rest on the installation' do
      account.update!(brand_color: '#11D135')

      brand = described_class.for(account: account)

      expect(brand.color).to eq '#11D135'
      expect(brand.name).to eq 'Chatwoot'
      expect(brand.url).to eq 'https://www.chatwoot.com'
    end

    # The settings form posts empty strings, so an administrator who opens the screen and saves
    # it untouched would otherwise strip the brand from every email the account sends.
    it 'falls back on a field the account left empty' do
      account.update!(brand_name: '')

      expect(described_class.for(account: account).name).to eq 'Chatwoot'
    end

    it 'keys the config like the installation, so a stored layout keeps resolving' do
      account.update!(brand_name: 'Guichê Web')

      config = described_class.for(account: account).config

      expect(config['BRAND_NAME']).to eq 'Guichê Web'
      expect(config['LOGO']).to eq '/brand-assets/logo.svg'
    end
  end

  describe '#logo_url' do
    it 'falls back to LOGO when it is a format email can render' do
      install('LOGO' => '/brand-assets/logo.png')

      with_modified_env 'FRONTEND_URL' => 'https://atendimento.example.com' do
        expect(described_class.for.logo_url).to eq 'https://atendimento.example.com/brand-assets/logo.png'
      end
    end

    it 'shows no logo rather than a broken one when LOGO is an SVG' do
      expect(described_class.for.logo_url).to eq ''
    end

    it 'leaves an absolute LOGO_EMAIL alone' do
      install('LOGO_EMAIL' => 'https://cdn.example.com/logo.png')

      expect(described_class.for.logo_url).to eq 'https://cdn.example.com/logo.png'
    end

    context 'with a logo attached to the account' do
      before do
        account.enable_features!('branded_email_templates')
        account.brand_logo_email.attach(
          io: Rails.root.join('spec/assets/avatar.png').open,
          filename: 'avatar.png',
          content_type: 'image/png'
        )
      end

      it 'serves it from this installation, so the URL does not expire like a signed one' do
        url = described_class.for(account: account).logo_url

        expect(url).to start_with 'http://localhost:3000/rails/active_storage/blobs/redirect/'
      end

      it 'ignores it when the feature is off' do
        account.disable_features!('branded_email_templates')

        expect(described_class.for(account: account).logo_url).to eq ''
      end
    end
  end
end
