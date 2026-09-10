# Per-account switches for the WhatsApp session providers, and the two are named for
# what they do, which is not the same thing for both.
#
# `uazapi` is on offer: an account that nobody has touched can create one, and the switch
# takes it away from one account. `native` is the other way round, and deliberately: it
# is being rolled out to named accounts rather than announced, so nothing is on offer
# until somebody says so. A flag whose absence means "yes" cannot do a restricted
# rollout, because every account created after the switch is flipped joins the rollout
# without anyone deciding that.
#
# What decides whether a provider is served **at all** is still its descriptor, not
# these: `native` needs a connector reachable on this deployment's Redis and answers
# `available?` on that. These narrow what the descriptor already allows, in both
# directions, and neither can offer a provider this deployment does not serve.
#
# They live in the `settings` jsonb (see the "Account-level toggles" section in
# AGENTS.md), keyed by name, so bit positions never drift between CE and Pro.
#
# Include this AFTER the other `store_accessor :settings` calls in Account: the writers
# below reach the store-accessor module through `super`.
module AccountWhatsappProviders
  extend ActiveSupport::Concern

  included do
    store_accessor :settings, :whatsapp_native_enabled, :whatsapp_uazapi_disabled
  end

  # The superadmin form posts "1"/"0" and the settings JSON schema only accepts booleans.
  def whatsapp_native_enabled=(value)
    super(ActiveModel::Type::Boolean.new.cast(value))
  end

  def whatsapp_uazapi_disabled=(value)
    super(ActiveModel::Type::Boolean.new.cast(value))
  end

  def whatsapp_session_provider_enabled?(provider)
    case provider.to_s
    when 'native' then whatsapp_native_enabled.present?
    when 'uazapi' then !whatsapp_uazapi_disabled
    else false
    end
  end
end
