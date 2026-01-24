# frozen_string_literal: true

# == Schema Information
#
# Table name: kanban_boards
#
#  id          :bigint           not null, primary key
#  description :text
#  name        :string           not null
#  settings    :jsonb            not null
#  steps_order :integer          default([]), is an Array
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_kanban_boards_on_account_id                 (account_id)
#  index_kanban_boards_on_account_id_and_created_at  (account_id,created_at)
#  index_kanban_boards_on_account_id_and_name        (account_id,name) UNIQUE
#  index_kanban_boards_on_account_id_and_updated_at  (account_id,updated_at)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class FazerAi::Kanban::Board < ApplicationRecord
  self.table_name = 'kanban_boards'

  belongs_to :account

  has_many :tasks,
           class_name: 'FazerAi::Kanban::Task',
           dependent: :destroy,
           inverse_of: :board
  has_many :steps,
           class_name: 'FazerAi::Kanban::BoardStep',
           dependent: :destroy,
           inverse_of: :board
  has_one :cancelled_step,
          -> { where(cancelled: true) },
          class_name: 'FazerAi::Kanban::BoardStep',
          inverse_of: :board,
          dependent: :nullify
  has_many :board_agents,
           class_name: 'FazerAi::Kanban::BoardAgent',
           dependent: :destroy,
           inverse_of: :board
  has_many :assigned_agents,
           through: :board_agents,
           source: :agent
  has_many :board_inboxes,
           class_name: 'FazerAi::Kanban::BoardInbox',
           dependent: :destroy,
           inverse_of: :board
  has_many :inboxes,
           through: :board_inboxes,
           source: :inbox

  validates :account, presence: true
  validates :name, presence: true, length: { maximum: 60 }, uniqueness: { scope: :account_id }
  validates :description, length: { maximum: 2000 }

  scope :ordered, -> { order(created_at: :asc) }

  after_destroy :clear_round_robin_queue
  after_save :reset_cancelled_on_first_or_last_step, if: :saved_change_to_steps_order?
  after_commit :dispatch_update_event, on: :update

  def sync_task_and_conversation_agents?
    settings['sync_task_and_conversation_agents'] == true
  end

  def auto_assign_task_to_agent?
    settings['auto_assign_task_to_agent'] == true
  end

  def auto_create_task_for_conversation?
    settings['auto_create_task_for_conversation'] == true
  end

  def auto_resolve_conversation_on_task_end?
    settings['auto_resolve_conversation_on_task_end'] == true
  end

  def auto_complete_task_on_conversation_resolve?
    settings['auto_complete_task_on_conversation_resolve'] == true
  end

  def first_step
    ordered_steps.first
  end

  def completed_step
    ordered_steps.last
  end

  def push_event_data
    {
      id: id,
      account_id: account_id,
      name: name,
      description: description,
      settings: settings,
      steps_order: steps_order,
      total_tasks_count: steps.sum(&:tasks_count),
      steps_summary: serialize_steps_summary,
      assigned_inbox_ids: inboxes.ids,
      assigned_inboxes: serialize_inboxes,
      assigned_agent_ids: assigned_agents.ids,
      assigned_agents: serialize_agents,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  def ordered_steps
    return steps.order(created_at: :asc) if steps_order.blank?

    steps.sort_by { |step| steps_order.index(step.id) || (steps_order.length + step.id) }
  end

  def includes_inbox?(inbox_id)
    board_inboxes.exists?(inbox_id: inbox_id)
  end

  accepts_nested_attributes_for :steps, allow_destroy: true

  private

  def serialize_steps_summary
    ordered_steps.map do |step|
      {
        id: step.id,
        name: step.name,
        color: step.color,
        tasks_count: step.tasks_count,
        cancelled: step.cancelled,
        inferred_task_status: step.inferred_task_status
      }
    end
  end

  def serialize_inboxes
    inboxes.map do |inbox|
      {
        id: inbox.id,
        name: inbox.name,
        channel_type: inbox.channel_type,
        provider: inbox.channel.try(:provider),
        medium: inbox.twilio? ? inbox.channel.try(:medium) : nil
      }.compact
    end
  end

  def serialize_agents
    assigned_agents.map do |agent|
      {
        id: agent.id,
        name: agent.name,
        email: agent.email,
        avatar_url: agent.avatar_url,
        availability_status: agent.availability_status
      }
    end
  end

  def dispatch_update_event
    Rails.configuration.dispatcher.dispatch(Events::Types::KANBAN_BOARD_UPDATED, Time.zone.now, board: reload)
  end

  def clear_round_robin_queue
    FazerAi::Kanban::BoardRoundRobinService.new(board: self).clear_queue
  end

  def reset_cancelled_on_first_or_last_step
    return if steps_order.blank?

    steps.where(id: [steps_order.first, steps_order.last], cancelled: true).find_each do |step|
      step.update!(cancelled: false)
    end
  end
end
