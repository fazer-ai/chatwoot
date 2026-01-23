# frozen_string_literal: true

# == Schema Information
#
# Table name: kanban_board_steps
#
#  id          :bigint           not null, primary key
#  cancelled   :boolean          default(FALSE), not null
#  color       :string           default("#475569"), not null
#  description :text
#  name        :string           not null
#  tasks_count :integer          default(0), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  board_id    :bigint           not null
#
# Indexes
#
#  index_kanban_board_steps_on_board_id  (board_id)
#
# Foreign Keys
#
#  fk_rails_...  (board_id => kanban_boards.id)
#
class FazerAi::Kanban::BoardStep < ApplicationRecord
  self.table_name = 'kanban_board_steps'

  belongs_to :board,
             class_name: 'FazerAi::Kanban::Board',
             inverse_of: :steps,
             touch: true
  has_many :tasks,
           class_name: 'FazerAi::Kanban::Task',
           dependent: :destroy,
           inverse_of: :board_step

  accepts_nested_attributes_for :tasks, allow_destroy: true

  validates :name, presence: true, length: { maximum: 60 }
  validates :description, length: { maximum: 120 }
  validates :color, presence: true
  validate :cancelled_step_not_first_or_last

  scope :ordered, -> { order(created_at: :asc) }

  before_save :uncancel_other_steps, if: -> { cancelled? && cancelled_changed? }
  after_create :add_to_board_order
  after_destroy :remove_from_board_order
  after_commit :dispatch_create_event, on: :create
  after_commit :dispatch_update_event, on: :update

  def inferred_task_status
    return 'open' if board.steps.count <= 1
    return 'cancelled' if cancelled?
    return 'completed' if last_step?

    'open'
  end

  def last_step?
    board.steps_order.last == id
  end

  def first_step?
    board.steps_order.first == id
  end

  def push_event_data
    {
      id: id,
      board_id: board_id,
      name: name,
      description: description,
      color: color,
      tasks_count: tasks_count,
      cancelled: cancelled,
      inferred_task_status: inferred_task_status,
      created_at: created_at,
      updated_at: updated_at
    }
  end

  private

  def cancelled_step_not_first_or_last
    return unless cancelled?

    errors.add(:cancelled, :cannot_be_first_step) if first_step?
    errors.add(:cancelled, :cannot_be_last_step) if last_step?
  end

  def uncancel_other_steps
    previously_cancelled_steps = board.steps.where(cancelled: true).where.not(id: id)
    previously_cancelled_steps.find_each do |step|
      step.update!(cancelled: false)
    end
  end

  def add_to_board_order
    board.with_lock do
      board.update!(steps_order: board.steps_order + [id])
    end
  end

  def remove_from_board_order
    return unless board

    board.with_lock do
      board.update!(steps_order: board.steps_order - [id])
    end
  end

  def dispatch_create_event
    Rails.configuration.dispatcher.dispatch(Events::Types::KANBAN_STEP_CREATED, Time.zone.now, step: self)
  end

  def dispatch_update_event
    Rails.configuration.dispatcher.dispatch(Events::Types::KANBAN_STEP_UPDATED, Time.zone.now, step: self)
  end
end
