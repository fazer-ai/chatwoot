# This migration handles the feature_flags bit position conflict introduced
# when merging upstream Chatwoot into chatwoot-pro.
#
# Upstream Chatwoot has:
#   bit 60 = captain_tasks, bit 61 = conversation_required_attributes, bit 62 = advanced_assignment
#
# chatwoot-pro inserts `kanban` at bit 60 (its original position), pushing:
#   bit 61 = captain_tasks, bit 62 = conversation_required_attributes, bit 63 = advanced_assignment
#
# For installations upgrading FROM upstream TO chatwoot-pro, bits 60+ must shift
# up by 1 to make room for kanban at bit 60 (which defaults to disabled/0).
#
# For existing chatwoot-pro installations, bits 61-63 were previously unused
# (those upstream features didn't exist yet), so this migration is skipped.
#
# Detection: if the `kanban_boards` table exists, this is already a chatwoot-pro
# installation and no shift is needed.
#
# NOTE: This migration is intentionally timestamped BEFORE
# 20251117090000_create_kanban_core_tables so that on upstream installs
# migrating to chatwoot-pro, it runs first (kanban_boards doesn't exist yet → shift).
# On existing chatwoot-pro installs, kanban_boards already exists → skip.
class ShiftFeatureFlagsForKanban < ActiveRecord::Migration[7.1]
  def up
    return if table_exists?(:kanban_boards)

    # Bits 0-59 stay unchanged (lower_mask captures them).
    # Bits 60+ shift left by 1, leaving bit 60 = 0 (kanban disabled).
    lower_mask = (1 << 60) - 1 # bits 0-59

    execute <<-SQL.squish
      UPDATE accounts
      SET feature_flags = (feature_flags & #{lower_mask}) | ((feature_flags >> 60) << 61)
      WHERE feature_flags >= #{1 << 60}
    SQL
  end

  def down
    # Reverse: shift bits 61+ down by 1, collapsing bit 60 (kanban) away.
    # Only applies to installations that were migrated (no kanban_boards table).
    return if table_exists?(:kanban_boards)

    lower_mask = (1 << 60) - 1

    execute <<-SQL.squish
      UPDATE accounts
      SET feature_flags = (feature_flags & #{lower_mask}) | ((feature_flags >> 61) << 60)
      WHERE feature_flags >= #{1 << 60}
    SQL
  end
end
