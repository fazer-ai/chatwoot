# Persist the AI agent on/off state on the conversation row instead of relying
# on the legacy `agente-off` label. The account-level flag chooses the source
# during the transition so existing automations (n8n reading the label) keep
# working until each account is migrated.
class AddAiStatusUsesAttributeToAccountsAndAiEnabledToConversations < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :ai_status_uses_attribute, :boolean, default: false, null: false
    add_column :conversations, :ai_enabled, :boolean, default: true, null: false
  end
end
