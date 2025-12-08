json.board_inboxes do
  json.array! @board_inboxes do |board_inbox|
    json.partial! 'api/v1/accounts/kanban/board_inboxes/board_inbox', board_inbox: board_inbox
  end
end
