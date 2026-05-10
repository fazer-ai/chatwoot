require 'administrate/base_dashboard'

class FunnelStageDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    name: Field::String,
    description: Field::Text,
    color: Field::String,
    position: Field::Number,
    active: Field::Boolean,
    closed: Field::Boolean,
    requires_loss_reason: Field::Boolean,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name
    position
    color
    active
    closed
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name
    description
    color
    position
    active
    closed
    requires_loss_reason
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    name
    description
    color
    position
    active
    closed
    requires_loss_reason
  ].freeze

  COLLECTION_FILTERS = {}.freeze

  def display_resource(funnel_stage)
    funnel_stage.name
  end
end
