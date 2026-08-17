json.synced_at @pins_synced_at.to_f

json.pins @conversation_pins do |conversation_pin|
  json.conversation_id conversation_pin.conversation.display_id
  json.pinned_at conversation_pin.created_at.to_f
end
