# Captures every IA-driven team assignment as an `AiAssignmentAttempt`
# row, so the "IA → Humano" audit report can answer
# "who was online in the target team at the exact moment the IA tried
# to hand off?" — without depending on the per-minute cron snapshot
# (which could go missing when `:scheduled_jobs` lagged behind).
#
# Hooks the `team.changed` event on the SyncDispatcher, which runs
# inline on the request thread, so `Current.user` is still set to the
# API caller (the n8n credential user for IA flows).
class AiAssignmentListener < BaseListener
  def team_changed(event)
    conversation = event.data[:conversation]
    return unless conversation
    return if conversation.team_id.blank?
    return unless AiAssignmentAttempt.ia_driven_user?(Current.user)

    AiAssignmentAttempt.create!(
      conversation: conversation,
      account_id: conversation.account_id,
      team: conversation.team,
      agent_assigned_id: conversation.assignee_id,
      triggered_by: Current.user,
      online_user_ids: online_team_member_ids(conversation)
    )
  rescue StandardError => e
    # The audit must never block the assignment. Swallow + log so a
    # transient Redis hiccup or a missing team doesn't 500 the API.
    Rails.logger.warn("[AiAssignmentListener] failed to record attempt for conversation=#{conversation&.id}: #{e.class}: #{e.message}")
  end

  private

  # "Online in the team" means anyone with a live heartbeat in
  # Chatwoot (`online` or `busy`) AND a member of the target team.
  # `busy` is included for the same reason the prior snapshot job did:
  # those agents are logged in and the auto-assigner could still have
  # routed to them.
  ACTIVE_STATUSES = %w[online busy].freeze

  def online_team_member_ids(conversation)
    team_member_ids = conversation.team.members.ids
    available = OnlineStatusTracker.get_available_users(conversation.account_id)
                                   .select { |_, status| ACTIVE_STATUSES.include?(status) }
                                   .keys.map(&:to_i)
    available & team_member_ids
  end
end
