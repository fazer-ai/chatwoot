# frozen_string_literal: true

module FazerAi::Concerns::Conversation
  extend ActiveSupport::Concern

  included do
    belongs_to :kanban_task,
               class_name: 'FazerAi::Kanban::Task',
               optional: true,
               inverse_of: :conversations

    prepend InstanceMethods
  end

  module InstanceMethods
    def list_of_keys
      super + %w[kanban_task_id]
    end
  end
end
