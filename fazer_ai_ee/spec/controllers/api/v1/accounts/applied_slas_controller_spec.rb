require 'rails_helper'

RSpec.describe 'Applied SLAs API', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:agent1) { create(:user, account: account, role: :agent) }
  let(:conversation1) { create(:conversation, account: account, assignee: agent1) }
  let(:sla_policy1) { create(:sla_policy, account: account) }

  before do
    account.enable_features!('sla')
    AppliedSla.destroy_all
  end

  # Upstream's template writes plain CSV.generate_line, so a name starting with `=` reached the
  # spreadsheet as a live formula. The fork's copy of the view (fazer_ai_ee/app/views) uses CSVSafe.
  it 'defuses a formula in the CSV download and leaves the rest of the name alone' do
    conversation1.assignee.update!(name: "=cmd|calc O'Keefe")
    create(:applied_sla, sla_policy: sla_policy1, conversation: conversation1, sla_status: 'missed')

    get "/api/v1/accounts/#{account.id}/applied_slas/download",
        headers: administrator.create_new_auth_token

    expect(response).to have_http_status(:success)
    expect(response.body).to include(%('=cmd|calc O'Keefe))
    expect(response.body).not_to include('&#39;')
  end
end
