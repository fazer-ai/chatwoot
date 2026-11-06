# Enterprise-only classes have no `prepend_mod_with` hook, so their fazer_ai_ee override is
# prepended here. Classes that do have the hook (CE classes Enterprise extends) need nothing:
# ChatwootApp.extensions lists fazer_ai_ee right after enterprise, and the hook picks up
# FazerAiEe::<same name> on its own.
#
# to_prepare runs again on every code reload in development, against the freshly loaded class.
Rails.application.config.to_prepare do
  next unless ChatwootApp.fazer_ai_ee?

  %w[
    Api::V1::Accounts::WhatsappCallsController
    Call
    Internal::ReconcilePlanConfigService
    SamlUserBuilder
    Voice::Conference::Manager
    Voice::InboundCallBuilder
    Voice::OutboundCallBuilder
    Voice::Provider::Twilio::ConferenceService
    Whatsapp::CallConversationBuilder
    Whatsapp::CallService
    Whatsapp::IncomingCallService
  ].each do |name|
    name.constantize.prepend("FazerAiEe::#{name}".constantize)
  end
end
