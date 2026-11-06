require 'rails_helper'

RSpec.describe 'SAML OmniAuth callback with an unusable assertion', type: :request do
  let!(:account) { create(:account) }

  before do
    allow(GlobalConfigService).to receive(:load).and_call_original
    allow(GlobalConfigService).to receive(:load).with('FRONTEND_URL', 'http://localhost:3000').and_return('http://www.example.com')
    account.enable_features!('saml')
    create(:account_saml_settings, account: account)
    OmniAuth.config.test_mode = true
    OmniAuth.config.mock_auth[:saml] = OmniAuth::AuthHash.new(
      provider: 'saml', uid: '123545', info: { name: 'Test User', email: 'broken@example.com' }
    )
  end

  it 'redirects to the login error when the assertion cannot produce a valid user' do
    with_modified_env FRONTEND_URL: 'http://www.example.com' do
      allow(User).to receive(:create).and_return(User.new(email: 'broken@example.com'))

      get "/omniauth/saml/callback?account_id=#{account.id}"

      expect(response).to redirect_to("http://www.example.com/app/login?error=saml-authentication-failed&sso_account_id=#{account.id}")
    end
  end
end
