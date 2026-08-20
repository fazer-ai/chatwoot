class Api::V1::Accounts::Whatsapp::SessionProvidersController < Api::V1::Accounts::BaseController
  # Only an administrator can create or convert an inbox, and this catalog exists to
  # drive those two forms.
  before_action :check_admin_authorization?

  # GET /api/v1/accounts/:account_id/whatsapp/session_providers
  #
  # The catalog the setup form renders itself from: which session providers this account
  # may pick, what each one asks for, and what it can do once connected. Legacy providers
  # are described too, so an existing inbox can be labelled and gated without the
  # dashboard carrying a provider name of its own.
  def index
    render json: { payload: session_descriptors.map { |d| d.to_h.merge('creatable' => creatable?(d)) } }
  end

  private

  def session_descriptors
    Whatsapp::Session::Registry.descriptors.select(&:session?)
  end

  # Whether this account may stand up a new inbox on this provider. The picker renders
  # itself from this, so the answer has to be the whole rule rather than the part this
  # layer happens to own.
  #
  # Legacy providers are still offered: they are frozen, not withdrawn, and they are what
  # most inboxes run on today. `available?` asks who serves the session, and nobody here
  # serves theirs, so it does not apply to them. Withdrawing them ahead of the removal is
  # then one env var on this line rather than a dashboard change.
  def creatable?(descriptor)
    return Whatsapp::Session::Registry.legacy_creatable? if descriptor.legacy?
    return false unless descriptor.available?

    Current.account.whatsapp_session_provider_enabled?(descriptor.key)
  end
end
