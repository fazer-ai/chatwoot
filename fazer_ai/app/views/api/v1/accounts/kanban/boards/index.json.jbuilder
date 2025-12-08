json.boards do
  json.array! @boards do |board|
    json.partial! 'board', board: board, with_steps: false
  end
end

json.preferences do
  defaults = FazerAi::Kanban::AccountUserPreference::DEFAULT_PREFERENCES
  json.merge! defaults.deep_merge(@preference&.preferences || {})
end
