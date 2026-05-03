json.payload do
  json.array! @history do |change|
    json.id change.id
    json.previous_stage change.previous_stage
    json.new_stage change.new_stage
    json.cycle change.cycle
    json.reason change.reason
    json.source change.source
    json.user_id change.user_id
    json.created_at change.created_at
  end
end
