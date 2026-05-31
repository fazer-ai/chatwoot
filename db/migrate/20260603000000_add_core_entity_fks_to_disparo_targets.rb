class AddCoreEntityFksToDisparoTargets < ActiveRecord::Migration[7.1]
  # disparo_targets is DERIVED data. Wire its loose integer columns to the core
  # tables so deleting a core entity prunes/keeps its targets at the DB level:
  #   conversation delete -> cascade (targets removed)
  #   contact delete      -> cascade (targets removed)
  #   inbox delete        -> nullify (target survives, inbox_id = NULL; never blocks the inbox delete)
  def up
    # ORPHAN SAFETY: adding a FK validates ALL existing rows. Prune/clean rows
    # that would otherwise block the constraint (derived data, safe to fix).
    # 1. conversation/contact orphans -> delete (the target is meaningless without them).
    execute(<<~SQL.squish)
      DELETE FROM disparo_targets
      WHERE NOT EXISTS (SELECT 1 FROM conversations WHERE conversations.id = disparo_targets.conversation_id)
         OR NOT EXISTS (SELECT 1 FROM contacts WHERE contacts.id = disparo_targets.contact_id)
    SQL
    # 2. stale inbox reference -> null (matches the nullify policy; the target survives).
    execute(<<~SQL.squish)
      UPDATE disparo_targets SET inbox_id = NULL
      WHERE inbox_id IS NOT NULL
        AND NOT EXISTS (SELECT 1 FROM inboxes WHERE inboxes.id = disparo_targets.inbox_id)
    SQL

    add_foreign_key :disparo_targets, :conversations, on_delete: :cascade
    add_foreign_key :disparo_targets, :contacts, on_delete: :cascade
    add_foreign_key :disparo_targets, :inboxes, on_delete: :nullify
  end

  def down
    remove_foreign_key :disparo_targets, :inboxes
    remove_foreign_key :disparo_targets, :contacts
    remove_foreign_key :disparo_targets, :conversations
  end
end
