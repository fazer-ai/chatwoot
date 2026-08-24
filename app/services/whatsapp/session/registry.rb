# The provider catalog. Answers "who serves this channel", "what can it do" and "what
# does its form look like" for every WhatsApp provider, including the legacy and cloud
# ones it does not serve, so the dashboard can drive itself from capabilities instead of
# provider-name literals.
#
# Most of the length below is the catalog literal itself, and it grows by a table entry
# every time a provider is described, so the module-length metric is measuring the data
# rather than the behavior.
module Whatsapp::Session::Registry # rubocop:disable Metrics/ModuleLength
  Descriptor = Whatsapp::Session::ProviderDescriptor
  Field = Whatsapp::Session::ProviderDescriptor::Field

  MARK_AS_READ = Field.new(name: 'mark_as_read', type: 'boolean', default: true).freeze
  PRESENCE_SUBSCRIBE = Field.new(name: 'presence_subscribe', type: 'boolean', default: false).freeze
  # Off by default, and behind the advanced toggle: the phone answers a history request
  # with everything it has (947 messages for one chat, measured), so an inbox opts into
  # that rather than discovering it on the first connect.
  HISTORY_SYNC = Field.new(name: 'history_sync', type: 'boolean', default: false).freeze

  DESCRIPTORS = [
    Descriptor.new(
      key: 'native',
      backend: 'Whatsapp::Session::Backends::Connector::Backend',
      beta: true,
      pairing_modes: %w[qr code],
      # No session_import: that is the Baileys credential import, which whatsmeow cannot
      # consume, and there is no such command in the contract. Its replacement for the
      # same problem (pairing without a QR the operator can scan) is the passkey relay,
      # which rides on the pairing commands.
      capabilities: %w[
        qr_pairing code_pairing echo_by_reserved_id edit revoke reactions typing presence
        presence_subscribe read_receipts mark_unread check_number profile_picture groups group_admin
        group_invites group_join_requests account_limits media_download
      ],
      fields: [MARK_AS_READ, PRESENCE_SUBSCRIBE]
    ),
    Descriptor.new(
      key: 'uazapi',
      backend: 'Whatsapp::Session::Backends::Uazapi::Backend',
      beta: true,
      pairing_modes: %w[qr code],
      # No group_invites: the captured build answers 405 on `/group/invitelink`, and the
      # group snapshot it does serve carries no invite code either. A capability that is
      # declared and then refused by the provider is a button that fails in the agent's
      # face, so it is not declared.
      capabilities: %w[
        qr_pairing code_pairing edit revoke reactions typing presence read_receipts check_number
        profile_picture groups group_admin account_limits media_download history_sync
      ],
      fields: [
        Field.new(name: 'base_url', type: 'url', required: true),
        Field.new(name: 'token', type: 'password', required: true, secret: true),
        MARK_AS_READ,
        PRESENCE_SUBSCRIBE,
        HISTORY_SYNC
      ]
    ),
    # Legacy: described so the UI can label and gate an existing inbox, never served here.
    # history_sync, despite being frozen: this one is not a new feature so much as the
    # provider's own data finally being kept. Baileys is the only provider that delivers
    # WhatsApp's offline replay, so a message that arrived while a Baileys inbox was down
    # is recoverable here and nowhere else.
    Descriptor.new(
      key: 'baileys',
      legacy: true,
      pairing_modes: %w[qr],
      capabilities: %w[
        qr_pairing session_import echo_by_reserved_id edit revoke reactions typing presence presence_subscribe
        read_receipts mark_unread check_number profile_picture groups group_admin group_invites
        group_join_requests account_limits media_download history_sync
      ]
    ),
    Descriptor.new(
      key: 'zapi',
      legacy: true,
      pairing_modes: %w[qr],
      capabilities: %w[qr_pairing revoke reactions read_receipts check_number]
    ),
    # typing and read_receipts included: the Cloud service implements both
    # (`toggle_typing_status` and `read_messages` post to the Graph API), and the
    # dashboard gates them by capability now.
    Descriptor.new(key: 'whatsapp_cloud', family: 'cloud',
                   capabilities: %w[reactions typing read_receipts media_download calls]),
    Descriptor.new(key: 'default', family: 'cloud', capabilities: %w[media_download])
  ].index_by(&:key).freeze

  class << self
    def descriptor(provider)
      DESCRIPTORS[provider.to_s]
    end

    def descriptors
      DESCRIPTORS.values
    end

    # Providers this layer serves. Legacy session providers are deliberately excluded:
    # they answer through their own services until they are removed.
    def session_provider?(provider)
      Whatsapp::Session::PROVIDERS.include?(provider.to_s)
    end

    # The QR/pairing family, legacy providers included. What sets it apart from the cloud
    # family is behavioral: a paired session is a real WhatsApp client, so there is no
    # 24-hour messaging window and no template requirement.
    def session_family?(provider)
      descriptor(provider)&.session? || false
    end

    # The class that turns this provider's webhook body into canonical events, or nil when
    # the provider does not deliver over HTTP (the connector publishes canonical events
    # already) or the inbox has left the session layer.
    def translator_for(channel)
      descriptor(channel.provider)&.backend_class&.translator
    end

    # Whether this inbox's provider runs outside the deployment's network. Unknown counts
    # as hosted: the public address is the one that works everywhere an internal one is
    # not strictly needed.
    def hosted?(channel)
      backend = descriptor(channel.provider)&.backend_class
      backend.nil? || backend.hosted?(channel)
    end

    # See `Backend.instance_fingerprint`. nil for a provider this layer does not serve, so
    # a caller comparing two of them is never fenced by a pair of nils.
    def instance_fingerprint(channel)
      descriptor(channel.provider)&.backend_class&.instance_fingerprint(channel)
    end

    def backend_for(channel)
      descriptor = descriptor(channel.provider)
      raise Whatsapp::Session::Errors::InvalidConfig, "#{channel.provider} is not served by the session layer" unless descriptor&.served?

      # A descriptor can name a backend that has not shipped yet, which is how a provider
      # gets described and labelled before it can be created. Saying so beats the
      # NoMethodError that constantizing nothing produces.
      backend = descriptor.backend_class
      raise Whatsapp::Session::Errors::NotSupported, "#{channel.provider} has no backend in this build" if backend.nil?

      backend.new(channel)
    end

    # The capabilities of a channel as the dashboard should see them: the descriptor's
    # list, minus what the instance turned off.
    def capabilities_for(channel)
      descriptor = descriptor(channel.provider)
      return [] if descriptor.nil?

      capabilities = descriptor.capabilities
      capabilities -= Whatsapp::Session::Capabilities::GROUP_CAPABILITIES unless groups_enabled?
      capabilities
    end

    # Kill switch for the whole group subsystem, legacy providers included: the Baileys
    # service delegates here so the capability list and `allow_group_creation` can never
    # disagree. The Baileys-era name still works, so an existing deployment does not have
    # to change its env on upgrade.
    def groups_enabled?
      value = ENV.fetch('WHATSAPP_GROUPS_ENABLED', nil) || ENV.fetch('BAILEYS_WHATSAPP_GROUPS_ENABLED', 'false')
      value == 'true'
    end

    # Whether the frozen providers are still offered when standing up a new inbox. They
    # are frozen, not withdrawn: existing inboxes keep working either way, and this is
    # what the deprecation flips when it starts.
    def legacy_creatable?
      ActiveModel::Type::Boolean.new.cast(ENV.fetch('WHATSAPP_LEGACY_PROVIDERS_CREATABLE', true))
    end

    def available_providers
      descriptors.select(&:available?).map(&:key)
    end
  end
end
