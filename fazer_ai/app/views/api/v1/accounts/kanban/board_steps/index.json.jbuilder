json.steps do
  json.array! @steps do |step|
    json.partial! 'board_step', step: step
  end
end
