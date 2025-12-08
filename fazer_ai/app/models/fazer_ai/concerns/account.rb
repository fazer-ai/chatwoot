# frozen_string_literal: true

module FazerAi::Concerns::Account
  extend ActiveSupport::Concern

  included do
    has_many :kanban_boards,
             class_name: 'FazerAi::Kanban::Board',
             dependent: :destroy_async,
             inverse_of: :account
    has_many :kanban_tasks,
             class_name: 'FazerAi::Kanban::Task',
             dependent: :destroy_async,
             inverse_of: :account
  end

  def kanban_feature_enabled?
    feature_enabled?('kanban_module')
  end
end
