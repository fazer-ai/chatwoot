require 'rails_helper'

RSpec.describe SuperAdmin::HealthScore::Metrics::ManagerEngagement do
  let(:on) { Date.current }
  let(:account) { create(:account) }

  it 'returns missing when the account has no manager role' do
    create(:user, account: account, role: :agent)

    result = described_class.new(account, on: on).compute

    expect(result).to include(missing: true, reason: 'no_manager_role')
  end

  it 'returns 100 when any manager signed in within the last 7 days' do
    manager = create(:user, account: account, role: :agent)
    AccountUser.find_by(user: manager, account: account).update!(role: :manager)
    manager.update!(current_sign_in_at: 2.days.ago)

    result = described_class.new(account, on: on).compute

    expect(result[:sub_score]).to eq(100)
    expect(result.dig(:raw, :recent_login)).to be true
  end

  it 'returns 0 when the only manager has not signed in recently' do
    manager = create(:user, account: account, role: :agent)
    AccountUser.find_by(user: manager, account: account).update!(role: :manager)
    manager.update!(current_sign_in_at: 30.days.ago)

    result = described_class.new(account, on: on).compute

    expect(result[:sub_score]).to eq(0)
    expect(result.dig(:raw, :recent_login)).to be false
  end
end
