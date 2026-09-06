# frozen_string_literal: true

require 'rails_helper'
require Rails.root.join 'spec/mailers/administrator_notifications/shared/smtp_config_shared.rb'

RSpec.describe ApplicationMailer do
  include_context 'with smtp config'

  let!(:account) { create(:account) }
  let!(:administrator) { create(:user, :administrator, email: 'admin@example.com', account: account) }
  let!(:inbox) { create(:inbox, account: account) }

  # AdministratorNotifications::BaseMailer picks its recipients off Current.account, so the
  # address list says which account was in Current while the mail rendered.
  def deliver
    AdministratorNotifications::ChannelNotificationsMailer
      .with(account: account)
      .whatsapp_disconnect(inbox)
      .deliver_now
  end

  it 'renders against the account it was parameterized with, not the caller one' do
    Current.account = create(:account)

    expect(deliver.to).to eq([administrator.email])
  end

  it 'gives the caller its Current back once the mail is built' do
    caller_account = create(:account)
    rule = create(:automation_rule, account: caller_account)
    Current.account = caller_account
    Current.executed_by = rule

    deliver

    expect(Current.account).to eq(caller_account)
    expect(Current.executed_by).to eq(rule)
  end

  it 'leaves Current empty for a caller that had nothing set' do
    deliver

    expect(Current.account).to be_nil
  end

  context 'with the branded layout' do
    before { InstallationConfig.where(name: 'BRAND_COLOR').first_or_create!(value: '#11D135') }

    it 'splits the brand colour by role: raw on the accent bar, darkened on link text' do
      body = deliver.body.decoded

      expect(body).to include 'background-color: #11D135'
      expect(body).to include "color: #{BrandColor.on_light('#11D135')}"
    end

    it 'falls back to LOGO when it is a format email clients render' do
      InstallationConfig.where(name: 'LOGO').first_or_initialize.update!(value: '/brand-assets/logo.png')

      with_modified_env 'FRONTEND_URL' => 'https://atendimento.example.com' do
        expect(deliver.body.decoded).to include 'src="https://atendimento.example.com/brand-assets/logo.png"'
      end
    end

    it 'shows no logo when LOGO is an SVG, which no email client renders' do
      InstallationConfig.where(name: 'LOGO').first_or_initialize.update!(value: '/brand-assets/logo.svg')

      expect(deliver.body.decoded).not_to include '<img'
    end

    it 'prefers LOGO_EMAIL over the LOGO fallback' do
      InstallationConfig.where(name: 'LOGO').first_or_initialize.update!(value: '/brand-assets/logo.png')
      InstallationConfig.where(name: 'LOGO_EMAIL').first_or_initialize.update!(value: 'https://cdn.example.com/email.png')

      expect(deliver.body.decoded).to include 'src="https://cdn.example.com/email.png"'
    end

    it 'resolves a configured logo path against FRONTEND_URL' do
      InstallationConfig.where(name: 'LOGO_EMAIL').first_or_create!(value: '/logo_email.png')

      with_modified_env 'FRONTEND_URL' => 'https://atendimento.example.com' do
        expect(deliver.body.decoded).to include 'src="https://atendimento.example.com/logo_email.png"'
      end
    end

    it 'leaves a logo already given as a full URL alone' do
      InstallationConfig.where(name: 'LOGO_EMAIL').first_or_create!(value: 'https://cdn.example.com/logo.png')

      expect(deliver.body.decoded).to include 'src="https://cdn.example.com/logo.png"'
    end
  end
end
