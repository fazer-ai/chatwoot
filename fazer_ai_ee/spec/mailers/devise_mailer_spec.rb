# frozen_string_literal: true

require 'rails_helper'

# Upstream's Enterprise copy of this e-mail is written in English; the fork's copy
# (fazer_ai_ee/app/views/devise/mailer) wins over it and reads the fork's translations.
RSpec.describe 'Devise::Mailer confirmation_instructions on top of Enterprise' do # rubocop:disable RSpec/DescribeClass
  let(:account) { create(:account) }
  let!(:confirmable_user) { create(:user, account: account) }
  let(:mail_body) { CGI.unescapeHTML(Devise::Mailer.confirmation_instructions(confirmable_user.reload, nil, {}).body.to_s) }

  # The mailer renders in the installation's default locale when no account is in scope.
  around do |example|
    default_locale = I18n.default_locale
    I18n.default_locale = :pt_BR
    example.run
  ensure
    I18n.default_locale = default_locale
  end

  before do
    confirmable_user.update!(confirmed_at: nil)
    confirmable_user.send(:generate_confirmation_token)
  end

  it 'renders the welcome e-mail in the reader language' do
    expect(mail_body).to include('Confirme seu e-mail para começar', 'Confirmar minha conta')
    expect(mail_body).not_to include('Confirm your email to get started')
  end

  it 'renders the e-mail update in the reader language, with the new address' do
    confirmable_user.update!(unconfirmed_email: 'novo@example.com')

    expect(mail_body).to include('Confirme seu novo endereço de e-mail', 'Novo e-mail', 'novo@example.com')
  end
end
