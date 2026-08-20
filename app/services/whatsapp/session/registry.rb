# The provider catalog. Answers "who serves this channel", "what can it do" and "what
# does its form look like" for every WhatsApp provider, including the legacy and cloud
# ones it does not serve, so the dashboard can drive itself from capabilities instead of
# provider-name literals.
module Whatsapp::Session::Registry
  Descriptor = Whatsapp::Session::ProviderDescriptor
  Field = Whatsapp::Session::ProviderDescriptor::Field

  MARK_AS_READ = Field.new(name: 'mark_as_read', type: 'boolean', default: true).freeze
  PRESENCE_SUBSCRIBE = Field.new(name: 'presence_subscribe', type: 'boolean', default: false).freeze

  DESCRIPTORS = [
    Descriptor.new(
      key: 'native',
      backend: 'Whatsapp::Session::Backends::Connector::Backend',
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
      pairing_modes: %w[qr code],
      # No group_invites: the captured build answers 405 on `/group/invitelink`, and the
      # group snapshot it does serve carries no invite code either. A capability that is
      # declared and then refused by the provider is a button that fails in the agent's
      # face, so it is not declared.
      capabilities: %w[
        qr_pairing code_pairing edit revoke reactions typing presence read_receipts check_number
        profile_picture groups group_admin account_limits media_download
      ],
      fields: [
        Field.new(name: 'base_url', type: 'url', required: true),
        Field.new(name: 'token', type: 'password', required: true, secret: true),
        # An instance the operator runs on this deployment's own network, which is offered
        # INTERNAL_HOST_URL instead of the public address for its webhook and for the
        # attachments it fetches.
        Field.new(name: 'use_internal_host', type: 'boolean', default: false),
        MARK_AS_READ,
        PRESENCE_SUBSCRIBE
      ]
    ),
    # Legacy: described so the UI can label and gate an existing inbox, never served here.
    Descriptor.new(
      key: 'baileys',
      legacy: true,
      pairing_modes: %w[qr],
      capabilities: %w[
        qr_pairing session_import echo_by_reserved_id edit revoke reactions typing presence presence_subscribe
        read_receipts mark_unread check_number profile_picture groups group_admin group_invites
        group_join_requests account_limits media_download
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

    def available_providers
      descriptors.select(&:available?).map(&:key)
    end
  end
end
