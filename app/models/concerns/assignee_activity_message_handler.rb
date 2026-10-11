module AssigneeActivityMessageHandler
  extend ActiveSupport::Concern

  private

  def create_assignee_change_activity(user_name)
    if @reopen_unassignment
      create_reopen_unassignment_activity
      @reopen_unassignment = nil
      # Auto-assignment can hand the reopened conversation to someone else in the same save.
      return if assignee_id.blank?
    end

    user_name = activity_message_owner(user_name)

    return unless user_name

    content = generate_assignee_change_activity_content(user_name)
    ::Conversations::ActivityMessageJob.perform_later(self, activity_message_params(content)) if content
  end

  # Runs with no user and no executed_by (a customer message did it), which would make
  # the generic path drop the activity; the reason is the point of this line anyway.
  def create_reopen_unassignment_activity
    content = I18n.t('conversations.activity.assignee.removed_not_in_reopen_team', **@reopen_unassignment, locale: account.locale)
    ::Conversations::ActivityMessageJob.perform_later(self, activity_message_params(content))
  end

  def generate_assignee_change_activity_content(user_name)
    params = { assignee_name: assignee&.name || '', user_name: user_name }
    key = assignee_id ? 'assigned' : 'removed'
    key = 'self_assigned' if self_assign? assignee_id
    I18n.t("conversations.activity.assignee.#{key}", **params)
  end

  def activity_message_owner(user_name)
    if !user_name && Current.executed_by.present?
      user_name = case Current.executed_by
                  when AssignmentPolicy
                    I18n.t('auto_assignment.policy_actor', policy_name: Current.executed_by.name)
                  when Inbox
                    I18n.t('auto_assignment.default_policy_name')
                  else
                    I18n.t('automation.system_name')
                  end
    end
    user_name
  end
end
