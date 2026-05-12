class AddMultiLanguageAiToAccounts < ActiveRecord::Migration[7.1]
  # Stored on its own boolean column instead of the `feature_flags` bitmap
  # because Chatwoot's bitmap is a signed bigint and only fits 63 flags
  # (the 64th flag overflows on save). It's also nicer for the Auris
  # integration: downstream code reads `account.multi_language_ai`
  # directly without going through `feature_enabled?`.
  def change
    add_column :accounts, :multi_language_ai, :boolean, default: false, null: false
  end
end
