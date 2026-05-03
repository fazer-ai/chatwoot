json.payload do
  json.conversation_id @result.conversation.display_id
  json.previous_stage @result.previous_stage
  json.new_stage @result.new_stage
  json.change do
    json.id @result.change.id
    json.cycle @result.change.cycle
    json.reason @result.change.reason
    json.source @result.change.source
    json.created_at @result.change.created_at
  end
end
