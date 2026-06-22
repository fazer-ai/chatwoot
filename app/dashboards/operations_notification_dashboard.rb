require 'administrate/base_dashboard'

class OperationsNotificationDashboard < Administrate::BaseDashboard
  SEVERITY_OPTIONS = OperationsNotification.severities.keys.map { |k| [k.titleize, k] }.freeze
  SCOPE_OPTIONS = OperationsNotification.scope_types.keys.map { |k| [k.titleize, k] }.freeze
  AUDIENCE_OPTIONS = OperationsNotification.audience_types.keys.map { |k| [k.titleize, k] }.freeze
  TRIGGER_OPTIONS = OperationsNotification.trigger_kinds.keys.map { |k| [k.titleize, k] }.freeze

  # Operators read the index/show pages from Brazil — render every
  # datetime in São Paulo so they don't have to mentally subtract UTC.
  LOCAL_TZ = 'America/Sao_Paulo'.freeze
  LOCAL_DATETIME_FORMAT = '%Y-%m-%d %H:%M:%S %Z'.freeze
  LOCAL_DATETIME = Field::DateTime.with_options(
    timezone: LOCAL_TZ,
    format: LOCAL_DATETIME_FORMAT
  )

  ATTRIBUTE_TYPES = {
    id: Field::Number,
    title: Field::String.with_options(searchable: true),
    body: Field::Text,
    severity: Field::Select.with_options(collection: SEVERITY_OPTIONS),
    scope_type: Field::Select.with_options(collection: SCOPE_OPTIONS),
    accounts_summary: Field::String.with_options(searchable: false),
    audience_type: Field::Select.with_options(collection: AUDIENCE_OPTIONS),
    audience_users_summary: Field::String.with_options(searchable: false),
    trigger_kind: Field::Select.with_options(collection: TRIGGER_OPTIONS),
    published_at: LOCAL_DATETIME,
    expires_at: LOCAL_DATETIME,
    # Rendered as a plain string instead of `Field::BelongsTo` because
    # `created_by` is a `SuperAdmin` (STI subclass of `User`). Administrate's
    # BelongsTo show partial builds `link_to([namespace, record])`, which
    # asks Rails for `super_admin_super_admin_path` — and that route does
    # not exist, blowing the show page up with a 500. We surface the
    # creator's name through a helper method on the model instead
    # (see `OperationsNotification#created_by_display`).
    created_by_display: Field::String.with_options(searchable: false),
    deleted_at: LOCAL_DATETIME,
    created_at: LOCAL_DATETIME,
    updated_at: LOCAL_DATETIME,
    operations_notification_acks: AcksCountLinkField
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    title
    severity
    scope_type
    audience_type
    trigger_kind
    published_at
    operations_notification_acks
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    title
    body
    severity
    scope_type
    accounts_summary
    audience_type
    audience_users_summary
    trigger_kind
    published_at
    expires_at
    created_by_display
    operations_notification_acks
    created_at
    updated_at
    deleted_at
  ].freeze

  # We override the form partial entirely (see
  # `app/views/super_admin/operations_notifications/_form.html.erb`) so
  # Administrate's auto-generated form is not used. FORM_ATTRIBUTES is
  # only consulted by `permitted_attributes`, which we override in the
  # controller — the list below is mostly cosmetic but kept aligned with
  # what the custom form actually submits.
  FORM_ATTRIBUTES = %i[
    title
    body
    severity
    scope_type
    audience_type
    trigger_kind
    expires_at
  ].freeze

  COLLECTION_FILTERS = {
    active: ->(resources) { resources.active },
    deleted: ->(resources) { resources.where.not(deleted_at: nil) }
  }.freeze

  def display_resource(operations_notification)
    "##{operations_notification.id} — #{operations_notification.title}"
  end

  # Administrate's index header builds the "New …" button with the
  # singular `resource_name`, and the sidebar uses the plural. We
  # override both directly so the labels do not depend on the i18n
  # backend picking up our YAML at boot — locales were silently
  # discarded once before (duplicate `activerecord:` key) and the
  # fallback "Operations Notification" leaked into the UI.
  def self.resource_name(opts = {})
    count = opts[:count] || 1
    count <= 1 ? 'notification' : 'Notification Center'
  end
end
