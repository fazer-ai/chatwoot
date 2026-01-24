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

  attr_accessor :skip_sync_callbacks

  before_destroy :cache_associations_for_callback
  after_commit :sync_agent_to_conversations, on: :create, unless: :skip_sync_callbacks
  after_commit :unassign_agent_from_conversations, on: :destroy, unless: :skip_sync_callbacks

  private

  def cache_associations_for_callback
    @cached_task = task
    @cached_agent_id = agent_id
  end

  def sync_agent_to_conversations
    return unless task.board.sync_task_and_conversation_agents?

    task.conversations.where(assignee_id: nil).find_each do |conversation|
      next unless conversation.inbox.assignable_agents.include?(agent)

      conversation.update!(assignee_id: agent_id)
    end
  end

  def unassign_agent_from_conversations
    return unless @cached_task&.board&.sync_task_and_conversation_agents?

    @cached_task.conversations.where(assignee_id: @cached_agent_id).find_each do |conversation|
      next_agent = find_next_assignable_agent(conversation)
      conversation.update!(assignee_id: next_agent&.id)
    end
  end

  def find_next_assignable_agent(conversation)
    inbox_agents = conversation.inbox.assignable_agents
    remaining_agents = User.joins(:kanban_task_agents).where(kanban_task_agents: { task_id: @cached_task.id })
    remaining_agents.find { |agent| inbox_agents.include?(agent) }
  end
end
