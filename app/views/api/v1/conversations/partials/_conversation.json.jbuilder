# TODO: Move this into models jbuilder
# Currently the file there is used only for search endpoint.
# Everywhere else we use conversation builder in partials folder

json.meta do
  json.sender do
    json.partial! 'api/v1/models/contact', formats: [:json], resource: conversation.contact
  end
  json.channel conversation.inbox.try(:channel_type)
  if conversation.assigned_entity.is_a?(AgentBot)
    json.assignee do
      json.partial! 'api/v1/models/agent_bot_slim', formats: [:json], resource: conversation.assigned_entity
    end
    json.assignee_type 'AgentBot'
  elsif conversation.assigned_entity&.account
    json.assignee do
      json.partial! 'api/v1/models/agent', formats: [:json], resource: conversation.assigned_entity
    end
    json.assignee_type 'User'
  end
  if conversation.team.present?
    json.team do
      json.partial! 'api/v1/models/team', formats: [:json], resource: conversation.team
    end
  end
  json.hmac_verified conversation.contact_inbox&.hmac_verified
end

json.id conversation.display_id
# Seeds `currentChat.messages` and is also the source for the `before` cursor
# in setActiveChat → fetchPreviousMessages. Must include private notes: the
# `chat` scope filters them out, so a trailing private note would never enter
# the store on cold open and the bubble wouldn't render until a non-private
# message arrived after it.
last_message = conversation.messages
                           .where(account_id: conversation.account_id)
                           .non_activity_messages
                           .hide_removed_reactions
                           .includes([{ attachments: [{ file_attachment: [:blob] }] }])
                           .reorder(created_at: :desc)
                           .first
json.messages last_message ? [last_message.push_event_data] : []

json.account_id conversation.account_id
json.uuid conversation.uuid
json.additional_attributes conversation.additional_attributes
json.agent_last_seen_at conversation.agent_last_seen_at.to_i
json.assignee_last_seen_at conversation.assignee_last_seen_at.to_i
json.can_reply conversation.can_reply?
json.contact_last_seen_at conversation.contact_last_seen_at.to_i
json.custom_attributes conversation.custom_attributes
json.inbox_id conversation.inbox_id
json.labels conversation.cached_label_list_array
json.muted conversation.muted?
json.snoozed_until conversation.snoozed_until
json.status conversation.status
json.created_at conversation.created_at.to_i
json.updated_at conversation.updated_at.to_f
json.timestamp conversation.last_activity_at.to_i
json.first_reply_created_at conversation.first_reply_created_at.to_i
json.unread_count conversation.unread_incoming_messages.count
if last_message
  json.last_non_activity_message do
    json.merge! last_message.push_event_data
    if last_message.reaction?
      target_id = last_message.content_attributes['in_reply_to']
      target = target_id.present? ? conversation.messages.find_by(id: target_id) : nil
      # strip_tags so the preview of an HTML/email target doesn't render as
      # literal "<p>..." markup in the chat list card. Wrap with `String.new`
      # because `strip_tags` returns `ActiveSupport::SafeBuffer`, which
      # Sidekiq's strict-args check rejects when this hash flows into a cable
      # broadcast job (event_data_presenter.rb shares the same pattern).
      if target&.content.present?
        plain_snippet = String.new(ActionController::Base.helpers.strip_tags(target.content))
        json.in_reply_to_snippet plain_snippet.truncate(60)
      end
    end
  end
else
  json.last_non_activity_message nil
end
json.last_activity_at conversation.last_activity_at.to_i
json.group_type conversation.group_type
json.priority conversation.priority
json.waiting_since conversation.waiting_since.to_i.to_i
json.sla_policy_id conversation.sla_policy_id
json.partial! 'enterprise/api/v1/conversations/partials/conversation', conversation: conversation if ChatwootApp.enterprise?
