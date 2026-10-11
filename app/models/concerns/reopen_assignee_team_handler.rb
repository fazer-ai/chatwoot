# Inbox setting reopen_assignee_team: when a customer's message reopens a
# conversation, an owner outside the inbox's reopen team is dropped, and until the
# conversation has an owner again every automatic pick draws only from that team.
module ReopenAssigneeTeamHandler
  extend ActiveSupport::Concern

  REOPEN_TEAM_RESTRICTED = 'reopen_team_restricted'.freeze

  included do
    # Included before AssignmentHandler, so the owner this settles is what the team
    # and takeover guards see.
    before_save :apply_reopen_assignee_team, if: -> { @reopen_assignee_check }
  end

  # Inbox setting: a customer message that reopens the conversation keeps the
  # assignee only while they are in the inbox's reopen team. Called before the
  # status save; the decision is taken inside that save, so the unassignment
  # rides on the same write.
  def drop_assignee_outside_reopen_team_on_save
    team = inbox.reopen_assignee_team
    return if team.blank? || assignee_id.blank?

    @reopen_assignee_check = { team: team, assignee_id: assignee_id }
  end

  # The one eligibility gate every automatic pick goes through: legacy assignment, the
  # v2 AssignmentService and the pick on a team change. While the conversation carries
  # the mark this rule leaves when it drops an owner, only members of the inbox's
  # reopen team can be picked; every other conversation keeps the pool it was given.
  def reopen_team_restricted?
    inbox.reopen_assignee_team_id.present? && additional_attributes&.dig(REOPEN_TEAM_RESTRICTED).present?
  end

  def reopen_eligible_agent_ids(agent_ids)
    return agent_ids unless reopen_team_restricted?

    agent_ids & inbox.reopen_assignee_team.members.ids
  end

  # Same gate over a relation of inbox members, as a subquery.
  def reopen_eligible_inbox_members(inbox_members)
    return inbox_members unless reopen_team_restricted?

    inbox_members.where(user_id: inbox.reopen_assignee_team.team_members.select(:user_id))
  end

  private

  # An agent can reassign or reopen the conversation after the customer's message
  # read it and before this save. Judging under the row lock leaves their action
  # alone: the owner is dropped only if the row still holds the one judged and is
  # still resolved or snoozed (an agent's manual reopen is exempt).
  def apply_reopen_assignee_team
    team, judged_id = @reopen_assignee_check.values_at(:team, :assignee_id)
    @reopen_assignee_check = nil
    owner_id, persisted_status, stored_attributes = self.class.lock.where(id: id).pick(:assignee_id, :status, :additional_attributes)
    return unless owner_id == judged_id && %w[resolved snoozed].include?(persisted_status)
    return if team.team_members.exists?(user_id: judged_id)

    @reopen_unassignment = { assignee_name: assignee.name, team_name: team.name }
    self.assignee = nil
    # Merged into the locked row's copy: the one in memory may predate another writer's keys.
    self.additional_attributes = (stored_attributes || {}).merge(REOPEN_TEAM_RESTRICTED => true)
  end

  def reopen_unassignment?
    @reopen_unassignment.present?
  end

  # The mark only governs the stretch between the drop and the next owner, however that
  # owner arrives. Read under the row lock so the write keeps keys another writer added
  # after this copy was loaded; a save that writes the column itself keeps its own value.
  def end_reopen_team_restriction
    stored_attributes = self.class.lock.where(id: id).pick(:additional_attributes) || {}
    return unless stored_attributes.key?(REOPEN_TEAM_RESTRICTED) || additional_attributes&.key?(REOPEN_TEAM_RESTRICTED)

    base = will_save_change_to_additional_attributes? ? additional_attributes : stored_attributes
    self.additional_attributes = base.except(REOPEN_TEAM_RESTRICTED)
  end
end
