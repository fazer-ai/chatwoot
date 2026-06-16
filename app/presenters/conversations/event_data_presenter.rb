class Conversations::EventDataPresenter < SimpleDelegator
  def push_data # rubocop:disable Metrics/MethodLength
    {
      additional_attributes: additional_attributes,
      can_reply: can_reply?,
      channel: inbox.try(:channel_type),
      contact_inbox: contact_inbox,
      group_type: group_type,
      id: display_id,
      inbox_id: inbox_id,
      messages: push_messages,
      last_non_activity_message: push_last_non_activity_message,
      labels: label_list,
      meta: push_meta,
      status: status,
      custom_attributes: custom_attributes,
      snoozed_until: snoozed_until,
      unread_count: unread_incoming_messages.count,
      first_reply_created_at: first_reply_created_at,
      priority: priority,
      waiting_since: waiting_since.to_i,
      **push_timestamps
    }
  end

  # Like #push_data but with message text normalized for external integrations (webhooks).
  def webhook_data
    push_data.merge(
      account: account.webhook_data,
      messages: webhook_push_messages
    )
  end

  private

  def push_messages
    [messages.where(account_id: account_id).chat.last&.push_event_data].compact
  end

  # Mirrors the conversation jbuilder so cable subscribers can refresh the chat
  # list preview after in-place reaction updates (the snake-cased field is read
  # by the frontend store and `MessagePreview` to derive the latest visible
  # message). Without this, the snapshot taken at fetch time stays stale.
  def push_last_non_activity_message
    msg = messages.where(account_id: account_id)
                  .non_activity_messages
                  .hide_removed_reactions
                  .reorder(created_at: :desc)
                  .first
    return nil unless msg

    data = msg.push_event_data
    if msg.reaction?
      target_id = msg.content_attributes['in_reply_to']
      target = target_id.present? ? messages.find_by(id: target_id) : nil
      # Strip HTML before truncating so email/HTML messages don't leak
      # "<p>..." markup into the chat-list preview as literal text.
      # `strip_tags` returns an `ActiveSupport::SafeBuffer`, which Sidekiq's
      # strict-args check rejects when this hash is passed to
      # `ActionCableBroadcastJob.perform_later`; coerce back to a plain String
      # so the cable broadcast doesn't 500 the controller via the dispatcher.
      if target&.content.present?
        plain_snippet = String.new(ActionController::Base.helpers.strip_tags(target.content))
        data[:in_reply_to_snippet] = plain_snippet.truncate(60)
      end
    end
    data
  end

  def webhook_push_messages
    [messages.where(account_id: account_id).chat.last&.webhook_push_event_data].compact
  end

  def push_meta
    {
      sender: contact.push_event_data,
      assignee: assigned_entity&.push_event_data,
      assignee_type: assignee_type,
      team: team&.push_event_data,
      hmac_verified: contact_inbox&.hmac_verified
    }
  end

  def push_timestamps
    {
      agent_last_seen_at: agent_last_seen_at.to_i,
      contact_last_seen_at: contact_last_seen_at.to_i,
      last_activity_at: last_activity_at.to_i,
      timestamp: last_activity_at.to_i,
      created_at: created_at.to_i,
      updated_at: updated_at.to_f
    }
  end
end
Conversations::EventDataPresenter.prepend_mod_with('Conversations::EventDataPresenter')
