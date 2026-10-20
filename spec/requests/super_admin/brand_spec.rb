require 'rails_helper'

RSpec.describe 'Super Admin sidebar version' do
  let(:super_admin) { create(:super_admin) }

  before do
    allow(Chatwoot).to receive(:config).and_return(Chatwoot.config.merge(version: '4.19.0-fazer-ai-pro.154'))
    sign_in(super_admin, scope: :super_admin)
  end

  it 'shows the full fork version and links to the fork release notes' do
    get '/super_admin'

    link = Nokogiri::HTML(response.body).at_css('a[href="https://fazer.ai/chatwoot-release-notes"]')
    expect(link.text.squish).to eq('v4.19.0-fazer-ai-pro.154')
    expect(response.body).not_to include('github.com/chatwoot/chatwoot/releases')
  end
end
