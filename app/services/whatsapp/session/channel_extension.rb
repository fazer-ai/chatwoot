# Prepended to Channel::Whatsapp. Everything the session family needs from the channel
# lives here, so the model itself only gains the provider list and this prepend, keeping
# the file (a heavy upstream-merge conflict point) untouched.
#
# Each override answers for the session providers and falls straight back to `super` for
# the legacy and cloud ones, so no existing provider changes behavior.
module Whatsapp::Session::ChannelExtension
  def session_provider?
    Whatsapp::Session::Registry.session_provider?(provider)
  end

  # Surfaced on the inbox payload so the dashboard gates features by capability instead
  # of by provider name.
  def session_capabilities
    Whatsapp::Session::Registry.capabilities_for(self)
  end

  def provider_service
    return super unless session_provider?

    Whatsapp::Session::Registry.backend_for(self)
  end

  def supports_reactions?
    return super unless session_provider?

    session_capabilities.include?('reactions')
  end

  def provider_connection_data
    data = super
    return data unless session_provider? && administrator?

    data[:error] = translated_provider_connection_error if provider_connection['error'].present?
    data.merge(provider_connection.slice('pairing_code', 'quarantine', 'ban').compact_blank.symbolize_keys)
  end

  private

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

  # Session providers that receive webhooks (uazapi) get a per-channel secret, which is
  # what authenticates the callback: the URL carries it and the controller compares it.
  def ensure_webhook_verify_token
    return super unless session_provider?

    provider_config['webhook_verify_token'] ||= SecureRandom.hex(16)
  end

  def translated_provider_connection_error
    key = provider_connection['error']
    I18n.t("errors.inboxes.channel.provider_connection.#{key}", default: key.to_s.humanize)
  end

  def administrator?
    Current.account_user&.administrator?
  end
end
