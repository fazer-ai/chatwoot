# Which inboxes have left this WhatsApp group.
#
# A group contact is account-scoped (its identifier is the group's own id), while a
# contact inbox is per inbox, so one WhatsApp group can belong to two inboxes of the same
# account. `group_left` was a single boolean on the shared contact, so one number leaving
# marked the group as left for every other number in it: the dashboard hid the composer
# and the group actions on threads that could still send, `sync_group` returned early and
# stopped refreshing them, and nothing on the inboxes that stayed could clear the flag,
# because only a rejoin clears it and they never left.
#
# The list is the record now, and the boolean is derived from it: it stays true only when
# every inbox this group is in has left, which is what it already meant for the single
# inbox case that is nearly all of them. External consumers reading
# `additional_attributes['group_left']` therefore keep the answer they had.
module WhatsappGroupMembership
  extend ActiveSupport::Concern

  LEFT = 'group_left'.freeze
  LEFT_INBOX_IDS = 'group_left_inbox_ids'.freeze

  def group_left_in?(inbox_id)
    inbox_id = inbox_id.to_i
    return false if inbox_id.zero?

    group_left_inbox_ids.include?(inbox_id)
  end

  def group_left_inbox_ids
    stored = additional_attributes&.dig(LEFT_INBOX_IDS)
    # A row written before the list existed says only "left", and it said it account
    # wide, so every inbox this group is in is what it meant. Same reading the data
    # migration writes down; this is what keeps a row it has not reached yet, or one
    # restored from a backup that predates it, from reading as "still in the group".
    return group_inbox_ids if stored.nil? && additional_attributes&.dig(LEFT).present?

    Array(stored).map(&:to_i).reject(&:zero?)
  end

  def mark_group_left!(inbox_id) = write_group_left_inbox_ids(inbox_id) { |ids, id| ids | [id] }

  def mark_group_rejoined!(inbox_id) = write_group_left_inbox_ids(inbox_id) { |ids, id| ids - [id] }

  private

  def group_inbox_ids = contact_inboxes.pluck(:inbox_id).compact.sort

  # Read-modify-write on a jsonb every inbox in this group shares, so it takes the row
  # lock: two of them leaving at the same moment would otherwise each build a list from
  # the state before the other, and whichever wrote second would erase the first.
  def write_group_left_inbox_ids(inbox_id)
    inbox_id = inbox_id.to_i
    return if inbox_id.zero?

    with_lock do
      ids = yield(group_left_inbox_ids, inbox_id).sort
      attributes = (additional_attributes || {}).merge(
        LEFT_INBOX_IDS => ids,
        LEFT => ids.present? && (group_inbox_ids - ids).empty?
      )
      update!(additional_attributes: attributes) if attributes != additional_attributes
    end
  end
end
