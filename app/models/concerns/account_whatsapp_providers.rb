# Per-account switches for the WhatsApp session providers, and they are named for what
# they do: a provider this deployment serves is offered to every account, and these take
# it away from one. Nothing has to be set for a provider to be on offer.
#
# What decides whether a provider is served at all is its descriptor, not these: `native`
# needs a connector reachable on this deployment's Redis and answers `available?` on
# that. These only withdraw something already on offer.
#
# They live in the `settings` jsonb (see the "Account-level toggles" section in
# AGENTS.md), keyed by name, so bit positions never drift between CE and Pro.
#
# Include this AFTER the other `store_accessor :settings` calls in Account: the writers
# below reach the store-accessor module through `super`.
module AccountWhatsappProviders
  extend ActiveSupport::Concern

  included do
    store_accessor :settings, :whatsapp_native_disabled, :whatsapp_uazapi_disabled
  end

  # The superadmin form posts "1"/"0" and the settings JSON schema only accepts booleans.
  def whatsapp_native_disabled=(value)
    super(ActiveModel::Type::Boolean.new.cast(value))
  end

  def whatsapp_uazapi_disabled=(value)
    super(ActiveModel::Type::Boolean.new.cast(value))
  end

  def whatsapp_session_provider_enabled?(provider)
    case provider.to_s
    when 'native' then !whatsapp_native_disabled
    when 'uazapi' then !whatsapp_uazapi_disabled
    else false
    end
  end
end
