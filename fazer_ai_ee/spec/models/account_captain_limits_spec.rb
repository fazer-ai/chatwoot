require 'rails_helper'

RSpec.describe Account do
  let(:account) { create(:account) }

  # Upstream clamps the remaining quota between 0 and the limit, which raises on a negative one.
  it 'reads a negative captain limit as no allowance instead of raising' do
    account.update!(limits: { captain_responses: -5, captain_documents: -1 })

    expect(account.usage_limits[:captain][:responses]).to eq(total_count: 0, current_available: 0, consumed: 0)
    expect(account.usage_limits[:captain][:documents]).to eq(total_count: 0, current_available: 0, consumed: 0)
  end

  it 'keeps a positive captain limit as it is' do
    account.update!(limits: { captain_responses: 7 })

    expect(account.usage_limits[:captain][:responses]).to include(total_count: 7, current_available: 7)
  end
end
