json.id target.id
json.conversation_id target.conversation_id
json.contact_id target.contact_id
json.inbox_id target.inbox_id
json.state target.state
json.primary_skip_reason target.primary_skip_reason
json.skip_reasons target.skip_reasons
json.shadow_run target.shadow_run
json.dispatch_id target.dispatch_id
# Raw phone is PII and is intentionally NOT persisted; only its presence is stored/exposed.
json.phone_present target.phone_present
json.created_at target.created_at
