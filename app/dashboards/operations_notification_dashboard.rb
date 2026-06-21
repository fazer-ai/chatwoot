require 'administrate/base_dashboard'

class OperationsNotificationDashboard < Administrate::BaseDashboard
  SEVERITY_OPTIONS = OperationsNotification.severities.keys.map { |k| [k.titleize, k] }.freeze
  SCOPE_OPTIONS = OperationsNotification.scope_types.keys.map { |k| [k.titleize, k] }.freeze
  AUDIENCE_OPTIONS = OperationsNotification.audience_types.keys.map { |k| [k.titleize, k] }.freeze
  TRIGGER_OPTIONS = OperationsNotification.trigger_kinds.keys.map { |k| [k.titleize, k] }.freeze

  ATTRIBUTE_TYPES = {
    id: Field::Number,
    title: Field::String.with_options(searchable: true),
    body: Field::Text,
    severity: Field::Select.with_options(collection: SEVERITY_OPTIONS),
    scope_type: Field::Select.with_options(collection: SCOPE_OPTIONS),
    account: Field::BelongsTo.with_options(class_name: 'Account'),
    audience_type: Field::Select.with_options(collection: AUDIENCE_OPTIONS),
    audience_value: Field::String,
    trigger_kind: Field::Select.with_options(collection: TRIGGER_OPTIONS),
    published_at: Field::DateTime,
    expires_at: Field::DateTime,
    created_by: Field::BelongsTo.with_options(class_name: 'User'),
    deleted_at: Field::DateTime,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
    operations_notification_acks: CountField
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
    account
    audience_type
    audience_value
    trigger_kind
    published_at
    expires_at
    created_by
    operations_notification_acks
    created_at
    updated_at
    deleted_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    title
    body
    severity
    scope_type
    account
    audience_type
    audience_value
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
end
