require 'administrate/field/base'

# Three Auris-flavor account toggles rendered as a single Administrate field
# in the Super Admin → Accounts edit page. The grid visual mirrors the
# Enterprise "All features" widget so operators get the same look-and-feel
# regardless of edition. All three are plain boolean columns on `accounts`
# so persistence stays trivial.
class AurisAccountSettingsField < Administrate::Field::Base
  def to_s
    'Auris settings'
  end

  def options
    [
      { key: :funnel_enabled,
        label: 'Funnel',
        checked: resource.funnel_enabled },
      { key: :ai_status_uses_attribute,
        label: 'AI status from attribute (off = legacy agente-off label)',
        checked: resource.ai_status_uses_attribute },
      { key: :multi_language_ai,
        label: 'Multi-language AI',
        checked: resource.multi_language_ai }
    ]
  end
end
