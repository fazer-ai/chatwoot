json.extract! board_inbox,
              :id,
              :board_id,
              :inbox_id,
              :created_at,
              :updated_at

if board_inbox.inbox.present?
  json.inbox do
    json.id board_inbox.inbox.id
    json.name board_inbox.inbox.name
    json.channel_type board_inbox.inbox.channel_type
    json.provider board_inbox.inbox.channel.try(:provider)
    json.medium board_inbox.inbox.channel.try(:medium) if board_inbox.inbox.twilio?
  end
else
  json.inbox nil
end
