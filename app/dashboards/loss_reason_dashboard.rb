require 'administrate/base_dashboard'

class LossReasonDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    name: Field::String,
    position: Field::Number,
    active: Field::Boolean,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    position
    active
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    position
    active
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    name
    position
    active
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(loss_reason)
    loss_reason.name
  end
end
