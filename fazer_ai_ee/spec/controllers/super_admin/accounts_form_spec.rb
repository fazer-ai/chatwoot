require 'rails_helper'

# Upstream's Enterprise form lists the General tab by name (name, locale, status, limits), so a
# field the dashboard adds never shows. The fork's copy (fazer_ai_ee/app/views/super_admin)
# puts every field the other tabs do not claim under General.
RSpec.describe 'Super Admin account form', type: :request do
  let(:super_admin) { create(:super_admin) }
  let(:account) { create(:account) }

  before { sign_in(super_admin, scope: :super_admin) }

  it 'shows the fork account settings on the General tab' do
    get "/super_admin/accounts/#{account.id}/edit"

    expect(response).to have_http_status(:success)
    %w[name hide_agent_unassigned_tab hide_agent_all_tab disable_agent_message_deletion limits].each do |field|
      expect(response.body).to include("account[#{field}]")
    end
  end
end
