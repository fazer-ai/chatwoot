json.audit_events do
  json.array! @audit_events do |audit_event|
    json.partial! 'api/v1/accounts/kanban/audit_events/audit_event', audit_event: audit_event
  end
end
