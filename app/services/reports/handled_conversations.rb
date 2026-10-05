# A conversation counts as handled by whoever sent at least one public message
# in it during the period. It is attributed to the sender, not to the assignee,
# so a conversation two agents replied to counts once for each of them, and an
# agent who never touched the conversations assigned to them handles none.
module Reports::HandledConversations
  METRIC = 'handled_conversations_count'.freeze

  SUMMARY_GROUP_BY = {
    'account' => 'messages.account_id',
    'agent' => 'messages.sender_id',
    'inbox' => 'messages.inbox_id',
    'team' => 'conversations.team_id'
  }.freeze

  module_function

  def metric?(name)
    name.to_s == METRIC
  end

  # Private notes, bot and automation replies and campaigns are left out: only a
  # message a person wrote to the customer makes a conversation handled. A live
  # chat campaign posts as its configured sender, a User, so it is told apart by
  # the campaign it carries.
  def messages(scope)
    scope.where(message_type: :outgoing, private: false, sender_type: 'User')
         .where("(messages.additional_attributes->'campaign_id') IS NULL")
         .unscope(:order)
  end

  # One row per conversation, ready for `count` (and groupdate's grouped count).
  def distinct_conversations(scope)
    messages(scope).select(:conversation_id).distinct
  end

  # { dimension_id => handled conversations } for a summary grouped by dimension.
  def summary_counts(account:, dimension_type:, range:, filters: {})
    group_by = SUMMARY_GROUP_BY[dimension_type.to_s]
    return {} if group_by.blank?

    scope = messages(account.messages.where(created_at: range))
    scope = scope.joins(:conversation) if dimension_type.to_s == 'team'
    scope = scope.where(inbox_id: filters[:inbox_id]) if filters[:inbox_id].present?
    scope = scope.where(sender_id: filters[:user_id]) if filters[:user_id].present?

    scope.group(group_by).distinct.count(:conversation_id)
  end
end
