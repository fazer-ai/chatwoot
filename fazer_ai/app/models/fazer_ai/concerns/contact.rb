# frozen_string_literal: true

module FazerAi::Concerns::Contact
  extend ActiveSupport::Concern

  included do
    has_many :kanban_task_contacts,
             class_name: 'FazerAi::Kanban::TaskContact',
             dependent: :delete_all,
             inverse_of: :contact
  end
end
