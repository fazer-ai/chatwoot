# Per-account toggles that gate the visibility of two left-sidebar entries:
#   inbox_view_menu_enabled  → controls the "Caixa de Entrada" item (route inbox_view)
#   help_center_menu_enabled → controls the "Central de Ajuda" portals group (/portals/new)
#
# Both default to false. Existing accounts will see these menus disappear after
# the migration runs — a super admin enables them per account from the Auris
# settings page. These flags intentionally stay OUT of `auris_settings` /
# `webhook_data` because they're navigation/access controls, not business
# behavior that an external integration needs to branch on.
class AddMenuVisibilityFlagsToAccounts < ActiveRecord::Migration[7.1]
  def change
    add_column :accounts, :inbox_view_menu_enabled, :boolean, default: false, null: false
    add_column :accounts, :help_center_menu_enabled, :boolean, default: false, null: false
  end
end
