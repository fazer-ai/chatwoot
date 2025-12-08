# frozen_string_literal: true

module FazerAi::Concerns::Inbox
  extend ActiveSupport::Concern

  included do
    has_many :kanban_board_inboxes,
             class_name: 'FazerAi::Kanban::BoardInbox',
             foreign_key: :inbox_id,
             dependent: :delete_all,
             inverse_of: :inbox
    has_many :kanban_boards,
             through: :kanban_board_inboxes,
             source: :board
  end
end
