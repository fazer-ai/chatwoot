json.payload do
  json.conversation do
    json.id @conversation.display_id
    json.uuid @conversation.uuid
    json.account_id @conversation.account_id
  end
  if @stage
    json.stage do
      json.id @stage.id
      json.name @stage.name
      json.description @stage.description
      json.position @stage.position
      json.closed @stage.closed
      json.active @stage.active
      json.color @stage.color
    end
  else
    json.stage nil
  end
end
