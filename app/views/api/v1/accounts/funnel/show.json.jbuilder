json.payload do
  json.stages do
    json.array! @stages do |stage|
      json.id stage.id
      json.name stage.name
      json.description stage.description
      json.position stage.position
      json.closed stage.closed
      json.color @labels_by_title[stage.name]&.color
      json.conversations do
        json.array!(@conversations_by_stage[stage.name] || []) do |conversation|
          json.partial! 'api/v1/accounts/funnel/conversation', formats: [:json], conversation: conversation
        end
      end
      json.count (@conversations_by_stage[stage.name] || []).size
    end
  end
end
