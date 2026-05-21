# Adds the `environment` flag that toggles the test/production account mode
# (Phase 1 of the WhatsApp simulator feature) and reserves a slot for the
# auto-created simulator inbox id we'll cache here in Phase 2.
#
# Backfill: every existing account is set to `production` (enum int = 1) so
# the rollout doesn't accidentally surface the "AMBIENTE DE TESTE" badge or
# the welcome-banner override on real customer accounts. Only fresh accounts
# created after this migration default to `test` (enum int = 0).
class AddEnvironmentToAccounts < ActiveRecord::Migration[7.1]
  def up
    add_column :accounts, :environment, :integer, default: 0, null: false
    add_column :accounts, :simulator_inbox_id, :bigint

    # rubocop:disable Rails/SkipsModelValidations
    Account.update_all(environment: 1)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def down
    remove_column :accounts, :simulator_inbox_id
    remove_column :accounts, :environment
  end
end
