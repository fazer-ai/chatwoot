json.payload do
  json.stages do
    json.array! @stages do |stage|
      conversations = @conversations_by_stage[stage.id] || []
      json.id stage.id
      json.name stage.name
      json.description stage.description
      json.position stage.position
      json.closed stage.closed
      json.color stage.color
      json.conversations do
        json.array!(conversations) do |conversation|
          json.partial! 'api/v1/accounts/funnel/conversation', formats: [:json], conversation: conversation
        end
      end
      json.count conversations.size
    end
  end
end
