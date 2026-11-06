require 'rails_helper'

RSpec.describe SamlUserBuilder do
  let(:email) { 'saml.user@example.com' }
  let(:auth_hash) do
    {
      'provider' => 'saml',
      'uid' => 'saml-uid-123',
      'info' => { 'email' => email, 'name' => 'SAML User', 'first_name' => 'SAML', 'last_name' => 'User' },
      'extra' => { 'raw_info' => { 'groups' => %w[Administrators Users] } }
    }
  end
  let(:account) { create(:account) }
  let(:builder) { described_class.new(auth_hash, account.id) }

  # Upstream hands back the unsaved user; the override reports a rejected assertion, which
  # the controller answers with the ordinary login error.
  context 'when the user cannot be created' do
    before { allow(User).to receive(:create).and_return(User.new(email: email)) }

    it 'reports a failed authentication instead of returning an unsaved user' do
      expect { builder.perform }.to raise_error(described_class::AuthenticationFailed)
    end

    it 'does not create an account association' do
      expect do
        expect { builder.perform }.to raise_error(described_class::AuthenticationFailed)
      end.not_to change(AccountUser, :count)
    end
  end

  # The reason the check sits on `create_user` rather than around the whole builder: a
  # failure after the user exists is ours, not the IdP's, and must not read as a login error.
  context 'when adding the user to the account fails' do
    it 'lets the failure through instead of reporting a failed authentication' do
      allow(AccountUser).to receive(:find_or_create_by).and_raise(ActiveRecord::RecordInvalid.new(AccountUser.new))

      expect { builder.perform }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
