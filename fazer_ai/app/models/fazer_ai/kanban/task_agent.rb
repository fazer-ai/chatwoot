# == Schema Information
#
# Table name: kanban_task_agents
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  agent_id   :bigint           not null
#  task_id    :bigint           not null
#
# Indexes
#
#  index_kanban_task_agents_on_agent_id              (agent_id)
#  index_kanban_task_agents_on_task_id               (task_id)
#  index_kanban_task_agents_on_task_id_and_agent_id  (task_id,agent_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (agent_id => users.id)
#  fk_rails_...  (task_id => kanban_tasks.id)
#
class FazerAi::Kanban::TaskAgent < ApplicationRecord
  self.table_name = 'kanban_task_agents'

  belongs_to :task, class_name: 'FazerAi::Kanban::Task'
  belongs_to :agent, class_name: 'User'

  validates :task_id, uniqueness: { scope: :agent_id }

  after_commit :auto_assign_agent_to_conversations, on: :create

  private

  def auto_assign_agent_to_conversations
    return unless task.board.auto_assign_agent_to_conversation?

    task.conversations.where(assignee_id: nil).find_each do |conversation|
      next unless conversation.inbox.assignable_agents.include?(agent)

      conversation.update!(assignee_id: agent_id)
    end
  end
end
