# Prepended to Channel::Whatsapp. Everything the session family needs from the channel
# lives here, so the model itself only gains the provider list and this prepend, keeping
# the file (a heavy upstream-merge conflict point) untouched.
#
# Each override answers for the session providers and falls straight back to `super` for
# the legacy and cloud ones, so no existing provider changes behavior.
module Whatsapp::Session::ChannelExtension
  # Registers the rollout gate as a real validation so it covers both paths that can
  # put an inbox on a session provider: creating one and converting an existing one
  # (`convert_provider!` pre-validates with `valid?` before it persists anything).
  def self.prepended(base)
    base.validate :validate_session_provider_enabled
  end

  def session_provider?
    Whatsapp::Session::Registry.session_provider?(provider)
  end

  # True for the legacy session providers too: callers that ask this want "is this a
  # paired phone" (no messaging window, no templates), not "is this served here".
  def session_family?
    Whatsapp::Session::Registry.session_family?(provider)
  end

  # Surfaced on the inbox payload so the dashboard gates features by capability instead
  # of by provider name.
  def session_capabilities
    Whatsapp::Session::Registry.capabilities_for(self)
  end

  # The channel talks to its provider in legacy provider terms, so it gets the facade;
  # everything inside the session layer asks for `session_backend` instead and speaks
  # the canonical command API.
  def provider_service
    return super unless session_provider?

    Whatsapp::Session::Facade.new(self)
  end

  def session_backend
    Whatsapp::Session::Registry.backend_for(self)
  end

  # A session provider fetches outbound media from Rails itself, so on an installation
  # where it cannot reach the public frontend URL (local Active Storage behind a private
  # network) the operator points INTERNAL_HOST_URL at something it can. Setting it is the
  # whole opt-in: unlike the Baileys flag this replaces, there is nothing else to turn on.
  #
  # Never for a hosted provider, though. The variable is a deployment-wide address, and an
  # installation that runs a connector alongside a hosted inbox would otherwise hand that
  # inbox a host on the other side of its own firewall: every outbound attachment on it
  # would fail, and nothing about the failure would point at this setting.
  def use_internal_host?
    return super unless session_provider?

    ENV['INTERNAL_HOST_URL'].present? && !Whatsapp::Session::Registry.hosted?(self)
  end

  def supports_reactions?
    return super unless session_provider?

    session_capabilities.include?('reactions')
  end

  # Three fields the legacy providers have no equivalent for. They are admin-only for the
  # same reason the QR is: a pairing code links the WhatsApp account. Built here so the
  # REST payload and the Action Cable push cannot drift, since both call this.
  def provider_connection_admin_data(connection = provider_connection)
    data = super
    return data unless session_provider?

    data.merge(connection.slice('pairing_code', 'quarantine', 'ban').compact_blank.symbolize_keys)
  end

  private

  # The account toggles are the rollout switch, and a picker that hides a provider is
  # not a gate: the API would happily create a `native` inbox for any account. Only new
  # records and provider changes are checked, so turning a toggle back off never makes
  # an inbox that already exists unsaveable.
  def validate_session_provider_enabled
    return unless session_provider?
    return unless new_record? || provider_changed?
    return if account&.whatsapp_session_provider_enabled?(provider)

    errors.add(:provider, I18n.t('errors.inboxes.channel.provider_not_enabled_for_account'))
  end

  # Session backends validate their config against the descriptor's field list, never
  # against the provider itself: saving an inbox must not depend on a provider being up.
  def validate_provider_config
    return super unless session_provider?

    descriptor = Whatsapp::Session::Registry.descriptor(provider)
    return errors.add(:provider, I18n.t('errors.inboxes.channel.provider_unavailable')) unless descriptor.available?

    invalid_keys = descriptor.backend_class.validate_config(provider_config || {})
    return if invalid_keys.empty?

    errors.add(:provider_config, I18n.t('errors.inboxes.channel.invalid_provider_config', keys: invalid_keys.join(', ')))
  end

  # Two identifiers every session inbox needs, both generated once and never shown: the
  # webhook secret that authenticates a provider callback (the URL carries it and the
  # controller compares it), and the session id the provider holds the session under.
  #
  # Deliberately not the phone number: the connector keys its whatsmeow store by this id,
  # and a re-pairing under a different number would otherwise land on top of the previous
  # session's device keys.
  def ensure_webhook_verify_token
    return super unless session_provider?

    provider_config['webhook_verify_token'] ||= SecureRandom.hex(16)
    provider_config['session_id'] = own_session_id
  end

  # Written from the stored value rather than from whatever came in, because
  # provider_config is permitted wholesale by the inbox API: an update that left this key
  # out used to mint a new id and orphan the session the connector is still holding under
  # the old one, and one supplied by a caller could name another inbox's session.
  def own_session_id
    stored = persisted? ? (provider_config_was || {})['session_id'] : nil
    stored.presence || SecureRandom.uuid
  end
end
