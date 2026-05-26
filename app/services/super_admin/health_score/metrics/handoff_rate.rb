# % of AI-active conversations in the last 30d that had at least one human
# outgoing message. High handoff rate = "AI is on but human always
# intervenes" = the AI isn't actually working for this customer.
#
# Score is inverted: 100 - (rate * 100). Lower handoff = higher score.
class SuperAdmin::HealthScore::Metrics::HandoffRate < SuperAdmin::HealthScore::Metrics::Base
  MIN_CONVERSATIONS_FOR_SIGNAL = 30

  def compute
    scope = ai_active_conversations
    total = scope.count
    return missing(:insufficient_volume, total_conversations: total) if total < MIN_CONVERSATIONS_FOR_SIGNAL

    handoff = scope.where(
      'EXISTS (SELECT 1 FROM messages m WHERE m.conversation_id = conversations.id ' \
      "AND m.message_type = #{Message.message_types[:outgoing]} AND m.sender_type = 'User')"
    ).count

    rate = handoff.to_f / total
    sub_score = ((1 - rate) * 100).clamp(0, 100).round
    present(sub_score, rate_pct: rate, total_conversations: total, handoff_count: handoff)
  end

  private

  def ai_active_conversations
    scope = account.conversations.where(created_at: (on - 30).beginning_of_day..on.end_of_day)
    return scope.where(ai_enabled: true) if account.ai_status_uses_attribute?

    scope.where.not(
      id: ActsAsTaggableOn::Tagging
            .joins(:tag)
            .where(taggable_type: 'Conversation', tags: { name: 'agente-off' })
            .select(:taggable_id)
    )
  end
end
