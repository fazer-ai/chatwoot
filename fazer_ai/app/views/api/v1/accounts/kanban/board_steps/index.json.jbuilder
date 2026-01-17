json.steps do
  json.array! @steps do |step|
    json.partial! 'board_step', step: step, filtered_count: @filtered_counts&.dig(step.id)
  end
end
