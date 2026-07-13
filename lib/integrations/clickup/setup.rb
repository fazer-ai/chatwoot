# Single question the whole app asks: is the ClickUp integration fully
# wired up? The frontend uses this to gate every operator-facing surface
# that would otherwise dead-end — "Meus Tickets" sidebar item, the flag
# icon that opens the feedback dialog, and the ticket_index route guard.
#
# "Fully wired" means BOTH:
# - the ClickUp API key was saved on Super Admin (CLICKUP_API_KEY), so
#   task creation and comment jobs can talk to ClickUp, AND
# - the webhook was registered (CLICKUP_WEBHOOK_ID present), so status
#   changes and "Resposta para o Cliente" updates flow back into the
#   ticket timeline.
#
# A key without a webhook still opens tickets but starves the operator of
# any update after that — worse UX than hiding the feature entirely,
# hence the AND. See RegisterWebhookJob for the auto-register flow that
# happens on key save, and the Super Admin "Registrar webhook" button for
# the manual override.
module Integrations::Clickup::Setup
  def self.ready?
    api_key_configured? && webhook_registered?
  end

  def self.api_key_configured?
    GlobalConfig.get('CLICKUP_API_KEY')['CLICKUP_API_KEY'].to_s.strip.present?
  end

  def self.webhook_registered?
    GlobalConfig.get('CLICKUP_WEBHOOK_ID')['CLICKUP_WEBHOOK_ID'].to_s.strip.present?
  end
end
