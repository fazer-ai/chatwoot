# frozen_string_literal: true

# == Schema Information
#
# Table name: kanban_account_user_preferences
#
#  id              :bigint           not null, primary key
#  preferences     :jsonb            not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_user_id :bigint           not null
#
# Indexes
#
#  index_kanban_account_user_preferences_on_account_user_id  (account_user_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_user_id => account_users.id)
#
class FazerAi::Kanban::AccountUserPreference < ApplicationRecord
  self.table_name = 'kanban_account_user_preferences'

  belongs_to :account_user

  validates :account_user_id, uniqueness: true

  DEFAULT_PREFERENCES = {
    'board_sorting' => {
      'sort' => 'updated_at',
      'order' => 'desc'
    },
    'favorite_board_ids' => [],
    'tasks_order' => {},
    'task_sorting' => {}
  }.freeze

  def tasks_order_for(step_id)
    preferences.dig('tasks_order', step_id.to_s) || []
  end

  def update_tasks_order!(step_id, order)
    preferences['tasks_order'] ||= {}
    preferences['tasks_order'][step_id.to_s] = order
    save!
  end
end
