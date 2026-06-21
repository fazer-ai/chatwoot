notification, ack = pair

json.id notification.id
json.title notification.title
json.body notification.body
json.severity notification.severity
json.trigger_kind notification.trigger_kind
json.scope_type notification.scope_type
json.audience_type notification.audience_type
json.published_at notification.published_at&.to_i
json.expires_at notification.expires_at&.to_i
json.acknowledged_at ack&.acknowledged_at&.to_i
