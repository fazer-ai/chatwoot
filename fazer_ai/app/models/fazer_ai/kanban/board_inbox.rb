# frozen_string_literal: true

# == Schema Information
#
# Table name: kanban_board_inboxes
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  board_id   :bigint           not null
#  inbox_id   :bigint           not null
#
# Indexes
#
#  index_kanban_board_inboxes_on_board_id               (board_id)
#  index_kanban_board_inboxes_on_board_id_and_inbox_id  (board_id,inbox_id) UNIQUE
#  index_kanban_board_inboxes_on_inbox_id               (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (board_id => kanban_boards.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#
class FazerAi::Kanban::BoardInbox < ApplicationRecord
  self.table_name = 'kanban_board_inboxes'

  belongs_to :board,
             class_name: 'FazerAi::Kanban::Board',
             inverse_of: :board_inboxes,
             touch: true
  belongs_to :inbox,
             inverse_of: :kanban_board_inboxes

  validates :inbox_id, uniqueness: { scope: :board_id }
  validate :inbox_belongs_to_same_account

  delegate :account, to: :board

  before_destroy :cleanup_task_conversations

  private

  def inbox_belongs_to_same_account
    return if inbox.blank? || board.blank?
    return if inbox.account_id == board.account_id

    errors.add(:inbox_id, I18n.t('kanban.inboxes.errors.mismatched_account'))
  end

  def cleanup_task_conversations
    task_ids = board.tasks.joins(:conversations).where(conversations: { inbox_id: inbox_id }).distinct.pluck(:id)

    Conversation
      .where(inbox_id: inbox_id, kanban_task_id: board.tasks.select(:id))
      .update_all(kanban_task_id: nil) # rubocop:disable Rails/SkipsModelValidations

    FazerAi::Kanban::Task.where(id: task_ids).find_each(&:touch) if task_ids.any?
  end
end
