class ActionCableBroadcastJob < ApplicationJob
  queue_as :critical
  include Events::Types

  CONVERSATION_UPDATE_EVENTS = [
    CONVERSATION_READ,
    CONVERSATION_UPDATED,
    TEAM_CHANGED,
    ASSIGNEE_CHANGED,
    CONVERSATION_STATUS_CHANGED
  ].freeze

  def perform(members, event_name, data)
    return if members.blank?

    broadcast_data = prepare_broadcast_data(event_name, data)
    broadcast_to_members(members, event_name, broadcast_data)
  end

  private

  # Ensures that only the latest available data is sent to prevent UI issues
  # caused by out-of-order events during high-traffic periods. This prevents
  # the conversation job from processing outdated data.
  def prepare_broadcast_data(event_name, data)
    return data unless CONVERSATION_UPDATE_EVENTS.include?(event_name)

    account = Account.find(data[:account_id])
    conversation = account.conversations.find_by!(display_id: data[:id])
    fresh_data = conversation.push_event_data.merge(account_id: data[:account_id])
    # Refresh the values, preserve the shape. Contact-bound broadcasts arrive
    # here already narrowed to the contact allowlist (ActionCableListener
    # #broadcast_to_contact), and rebuilding from the conversation row would
    # hand the contact back the whole agent payload. Keeping to the keys the
    # caller sent means this job never has to know which those are — including
    # the ones Pro and Enterprise add.
    fresh_data = fresh_data.slice(*data.keys)
    # The refreshed payload comes from the conversation row; transient per-event
    # metadata set by the listener (eg. `source: 'reaction_toggle'` so the
    # frontend skips SCROLL_TO_MESSAGE) lives only on the original `data` hash,
    # so carry it forward explicitly.
    fresh_data[:event_metadata] = data[:event_metadata] if data[:event_metadata].present?
    fresh_data
  end

  def broadcast_to_members(members, event_name, broadcast_data)
    members.each do |member|
      ActionCable.server.broadcast(
        member,
        {
          event: event_name,
          data: broadcast_data
        }
      )
    end
  end
end
