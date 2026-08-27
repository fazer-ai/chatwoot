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
end
