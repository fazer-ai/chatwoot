module AssignmentHandler
  extend ActiveSupport::Concern
  include Events::Types

  included do
    before_save :ensure_assignee_is_from_team
    # Declared after the team callback on purpose: that one can null the assignee
    # when the new team excludes them, and the guard has to see the final value.
    before_save :ensure_assignment_not_taken, if: :assignee_id_changed?
    after_commit :notify_assignment_change, :process_assignment_changes
  end

  private

  # The conversation belongs to whoever claimed it first. Only the current
  # assignee and administrators get to change that; every other agent is turned
  # away with a 409.
  def ensure_assignment_not_taken
    return if new_record? || assignee_id_was.blank?
    return unless inbox.prevent_assignment_takeover?
    return if assignment_change_allowed?

    raise CustomExceptions::Conversation::AlreadyAssigned.new(
      agent_name: account.users.find_by(id: assignee_id_was)&.available_name
    )
  end

  # `Current.user` is the same discriminator `process_assignment_activities`
  # already relies on to tell a human action apart from an automated one:
  # round-robin, automation rules (AsyncDispatcher -> job) and voice webhooks
  # reach this callback with it unset and pass straight through. BulkActionsJob
  # and Macros::ExecutionService set it deliberately, because they *are* human
  # actions, which is why they are guarded too.
  #
  # The `is_a?(User)` test is not just a nil check: a bot-authenticated request
  # puts an AgentBot in `Current.user`, and its id lives in a different sequence
  # than `users.id`, so comparing the two would match by coincidence.
  def assignment_change_allowed?
    return true unless Current.user.is_a?(User)
    return true if Current.user.id == assignee_id_was

    account.account_users.exists?(user_id: Current.user.id, role: :administrator)
  end

  def ensure_assignee_is_from_team
    return unless team_id_changed?

    validate_current_assignee_team
    self.assignee ||= find_assignee_from_team
  end

  def validate_current_assignee_team
    self.assignee_id = nil if team&.members&.exclude?(assignee)
  end

  def find_assignee_from_team
    return if team&.allow_auto_assign.blank?

    team_members_with_capacity = inbox.member_ids_with_assignment_capacity & team.members.ids
    ::AutoAssignment::AgentAssignmentService.new(conversation: self, allowed_agent_ids: team_members_with_capacity).find_assignee
  end

  def notify_assignment_change
    {
      ASSIGNEE_CHANGED => -> { saved_change_to_assignee_id? },
      TEAM_CHANGED => -> { saved_change_to_team_id? }
    }.each do |event, condition|
      condition.call && dispatcher_dispatch(event, previous_changes)
    end
  end

  def process_assignment_changes
    process_assignment_activities
  end

  def process_assignment_activities
    user_name = Current.user.name if Current.user.present?
    if saved_change_to_team_id?
      create_team_change_activity(user_name)
    elsif saved_change_to_assignee_id?
      create_assignee_change_activity(user_name)
    end
  end

  def self_assign?(assignee_id)
    assignee_id.present? && Current.user&.id == assignee_id
  end
end
