# frozen_string_literal: true

# == Schema Information
#
# Table name: kanban_board_agents
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  agent_id   :bigint           not null
#  board_id   :bigint           not null
#
# Indexes
#
#  index_kanban_board_agents_on_agent_id               (agent_id)
#  index_kanban_board_agents_on_board_id               (board_id)
#  index_kanban_board_agents_on_board_id_and_agent_id  (board_id,agent_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (agent_id => users.id)
#  fk_rails_...  (board_id => kanban_boards.id)
#
class FazerAi::Kanban::BoardAgent < ApplicationRecord
  self.table_name = 'kanban_board_agents'

  belongs_to :board,
             class_name: 'FazerAi::Kanban::Board',
             inverse_of: :board_agents,
             touch: true
  belongs_to :agent,
             class_name: 'User',
             inverse_of: :kanban_board_agents

  delegate :account, to: :board

  validates :agent_id, uniqueness: { scope: :board_id }
  validate :agent_belongs_to_account

  after_create :add_agent_to_round_robin_queue
  after_destroy :remove_agent_from_round_robin_queue
  after_destroy :unassign_from_tasks

  private

  def add_agent_to_round_robin_queue
    FazerAi::Kanban::BoardRoundRobinService.new(board: board).add_agent_to_queue(agent_id)
  end

  def remove_agent_from_round_robin_queue
    FazerAi::Kanban::BoardRoundRobinService.new(board: board).remove_agent_from_queue(agent_id)
  end

  def unassign_from_tasks
    task_ids = FazerAi::Kanban::Task
               .joins(:task_agents)
               .where(board_id: board_id, kanban_task_agents: { agent_id: agent_id })
               .distinct
               .pluck(:id)

    FazerAi::Kanban::TaskAgent
      .joins(:task)
      .where(kanban_tasks: { board_id: board_id }, agent_id: agent_id)
      .destroy_all

    FazerAi::Kanban::Task.where(id: task_ids).find_each(&:touch) if task_ids.any?
  end

  def agent_belongs_to_account
    return if agent.blank? || board.blank?
    return if account.users.exists?(id: agent_id)

    errors.add(:agent_id, I18n.t('kanban.agents.errors.invalid_agent'))
  end
end
