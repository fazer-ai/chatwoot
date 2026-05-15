require 'administrate/field/base'

# Sidebar visibility toggles rendered as a dedicated Administrate field in the
# Super Admin → Accounts edit page. Sibling to AurisAccountSettingsField, but
# kept separate so these flags never leak into the webhook payload — they're
# pure navigation/access controls, not business behavior.
class AurisAccountMenusField < Administrate::Field::Base
  def to_s
    'Auris menus'
  end

  def options
    [
      { key: :inbox_view_menu_enabled,
        label: 'Caixa de Entrada',
        checked: resource.inbox_view_menu_enabled },
      { key: :help_center_menu_enabled,
        label: 'Central de Ajuda',
        checked: resource.help_center_menu_enabled }
    ]
  end
end
