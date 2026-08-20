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
    base.after_update_commit :handle_provider_config_change, if: :saved_change_to_provider_config?
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

  # The destroy path alone: `convert_provider!` reaches the provider service directly.
  # Destruction goes ahead whether or not the provider answered, which is why the model
  # swallows a teardown failure here, and why the registration is released separately: the
  # teardown stops at the disconnect when that fails, deliberately, because on a
  # conversion the webhook has to survive a rollback. There is no inbox left for it to
  # survive for, so it goes. On the ordinary path this repeats a withdrawal the teardown
  # already made, which is one request against an instance we are done with.
  def disconnect_channel_provider
    return super unless session_provider?

    super
  ensure
    session_backend.release_registration if session_provider?
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

  # Both account limits in one write, which is one broadcast. The model has a setter per
  # limit and each of them persists and broadcasts the whole provider_connection; the two
  # cable payloads are separate jobs with no order between them, so the first, still
  # carrying the cap from before this poll, can arrive last and put a stale banner back on
  # a record that is already right. The normalization mirrors those setters, nil meaning
  # "not reported this time" in both.
  def update_account_limits!(limits)
    limits = (limits || {}).with_indifferent_access
    updates = {}
    updates['reachout_time_lock'] = limits[:reachout_time_lock].deep_stringify_keys unless limits[:reachout_time_lock].nil?
    unless limits[:new_chat_cap].nil?
      updates['new_chat_cap'] = limits[:new_chat_cap].to_h.deep_stringify_keys.slice(*Channel::Whatsapp::NEW_CHAT_CAP_KEYS)
    end
    return if updates.empty?

    with_lock { update_provider_connection!(provider_connection.merge(updates)) }
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

  # Two things a session inbox's config can change that the provider has to be told about,
  # and neither of them changes the provider key, so nothing else in the layer notices.
  #
  # Inline, like the teardown a destroy and a conversion already run: one of these needs
  # the credentials that just left the record, and a job would have to carry them through
  # Redis to use them.
  def handle_provider_config_change
    return unless session_provider?
    # A conversion changes the provider and the config in the same save, and
    # `convert_provider!` has already torn the old provider down and emptied the record.
    return if saved_change_to_provider?

    previous = self.class.find(id)
    previous.provider_config = saved_change_to_provider_config.first || {}
    moved_instance?(previous) ? let_go_of(previous) : refresh_registration(previous)
  rescue Whatsapp::Session::Errors::Error => e
    # This runs after the commit, so raising would answer a save that already succeeded
    # with a 500, and neither half of this is something the save depended on.
    Rails.logger.warn("[WHATSAPP SESSION] provider config change on inbox ##{inbox&.id} left the provider behind: #{e.message}")
  end

  # False for every save that did not touch the credentials, and for a backend with no
  # instance to name: the connector keys its session by an id this cannot change.
  def moved_instance?(previous)
    fingerprint = Whatsapp::Session::Registry.instance_fingerprint(previous)
    fingerprint.present? && fingerprint != Whatsapp::Session::Registry.instance_fingerprint(self)
  end

  # The inbox now points at another instance of the same provider: a rotated token, a moved
  # address, a second instance on the same hosted service. The connection record goes on
  # reporting the session the previous instance had, down to the number it was paired with,
  # while the new one has never been told where to deliver: the inbox reads as connected and
  # receives nothing until somebody thinks to reconnect it.
  #
  # So the record is emptied, which is what puts the dashboard back on "connect", and the
  # registration on the instance being left behind is withdrawn. Registering the new one is
  # deliberately not done here: that is what `connect` does, it is the operator's action,
  # and on an instance that is not paired it would start a pairing nobody is watching.
  def let_go_of(previous)
    with_lock { update_provider_connection!({}) }
    Whatsapp::Session::Registry.backend_for(previous).release_registration
  end

  # The same instance, at an address it was never told about: `use_internal_host` is what
  # decides between the public frontend URL and the one that works inside the deployment's
  # own network, and the provider has no way to learn that a form was edited. Outbound media
  # follows the new choice on the next message, while the webhook would go on arriving at the
  # old address, or stop arriving at all, which on the closed network this option exists for
  # is the whole of the inbox's inbound traffic.
  def refresh_registration(previous)
    return if previous.use_internal_host? == use_internal_host?

    session_backend.ensure_registration
  end

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

    provider_config['webhook_verify_token'] = kept('webhook_verify_token') { SecureRandom.hex(16) }
    provider_config['session_id'] = kept('session_id') { SecureRandom.uuid }
  end

  # Written from the stored value rather than from whatever came in, because
  # provider_config is permitted wholesale by the inbox API and neither of these keys is
  # shown on the form. An update that leaves one out used to mint a new one: a new session
  # id orphans the session the connector is still holding under the old one, and a new
  # webhook secret leaves the provider posting to a URL this app now answers 401, so the
  # inbox goes quiet until somebody reconnects it.
  #
  # One handed in by a caller is ignored for the same reason it is not asked for: it could
  # name another inbox's session, or make the secret a value somebody else chose.
  def kept(key)
    stored = persisted? ? (provider_config_was || {})[key] : nil
    stored.presence || yield
  end
end
