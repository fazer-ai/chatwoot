# frozen_string_literal: true

module FazerAi::Concerns::AccountUser
  extend ActiveSupport::Concern

  included do
    has_many :kanban_assigned_tasks,
             ->(account_user) { where(account_id: account_user.account_id) },
             through: :user

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
    has_one :kanban_preference,
            class_name: 'FazerAi::Kanban::AccountUserPreference',
            dependent: :destroy,
            inverse_of: :account_user
  end
end
