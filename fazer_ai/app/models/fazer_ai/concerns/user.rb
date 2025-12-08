# frozen_string_literal: true

module FazerAi::Concerns::User
  extend ActiveSupport::Concern

  included do
    has_many :kanban_task_agents,
             class_name: 'FazerAi::Kanban::TaskAgent',
             foreign_key: :agent_id,
             inverse_of: :agent,
             dependent: :destroy
    has_many :kanban_assigned_tasks,
             through: :kanban_task_agents,
             source: :task

    has_many :kanban_created_tasks,
             class_name: 'FazerAi::Kanban::Task',
             foreign_key: :created_by_id,
             inverse_of: :creator,
             dependent: :nullify
    has_many :kanban_board_agents,
             class_name: 'FazerAi::Kanban::BoardAgent',
             foreign_key: :agent_id,
             inverse_of: :agent,
             dependent: :destroy_async
    has_many :kanban_audit_events,
             class_name: 'FazerAi::Kanban::AuditEvent',
             foreign_key: :performed_by_id,
             inverse_of: :actor,
             dependent: :nullify
  end
end
