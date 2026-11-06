# frozen_string_literal: true

require 'rails_helper'

# Upstream asserts the FRONTEND_URL fallback, so its example only passes where nobody set
# one; any dev machine with a .env has it. Superseded by this one, which names the value
# (fazer_ai_ee/spec/support/superseded_upstream_examples.rb).
RSpec.describe AccountSamlSettings, type: :model do
  let(:account) { create(:account) }

  it 'automatically generates sp_entity_id when creating' do
    with_modified_env FRONTEND_URL: 'https://chat.example.com' do
      settings = build(:account_saml_settings, account: account, sp_entity_id: nil)
      expect(settings).to be_valid
      settings.save!
      expect(settings.sp_entity_id).to eq("https://chat.example.com/saml/sp/#{account.id}")
    end
  end
end
