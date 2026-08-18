# Per-account rollout switches for the WhatsApp session providers. They gate which
# providers an account may create or convert to, so the new layer can go out to a few
# accounts at a time instead of to the whole instance at once.
#
# They live in the `settings` jsonb (see the "Account-level toggles" section in
# AGENTS.md), keyed by name, so bit positions never drift between CE and Pro.
#
# Include this AFTER the other `store_accessor :settings` calls in Account: the writers
# below reach the store-accessor module through `super`.
module AccountWhatsappProviders
  extend ActiveSupport::Concern

  included do
    store_accessor :settings, :whatsapp_native_enabled, :whatsapp_uazapi_enabled
  end

  # The superadmin form posts "1"/"0" and the settings JSON schema only accepts booleans.
  def whatsapp_native_enabled=(value)
    super(ActiveModel::Type::Boolean.new.cast(value))
  end

  def whatsapp_uazapi_enabled=(value)
    super(ActiveModel::Type::Boolean.new.cast(value))
  end

  # Opt-in during the rollout. It flips to opt-out (`!= false`) at GA, which is the only
  # change these two methods need.
  def whatsapp_session_provider_enabled?(provider)
    case provider.to_s
    when 'native' then whatsapp_native_enabled == true
    when 'uazapi' then whatsapp_uazapi_enabled == true
    else false
    end
  end
end
