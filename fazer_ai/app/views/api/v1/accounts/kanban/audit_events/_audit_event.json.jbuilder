json.extract! audit_event,
              :id,
              :account_id,
              :task_id,
              :performed_by_id,
              :action,
              :metadata,
              :created_at,
              :updated_at

if audit_event.actor.present?
  json.actor do
    json.id audit_event.actor.id
    json.name audit_event.actor.name
    json.email audit_event.actor.email
  end
else
  json.actor nil
end
