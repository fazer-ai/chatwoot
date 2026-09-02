class ConversationPolicy < ApplicationPolicy
  def index?
    true
  end

  def destroy?
    administrator?
  end

  def show?
    administrator? || agent_bot? || agent_can_view_conversation?
  end

  # Narrower than `show?`, which lets any bot in the account read any conversation. A read
  # receipt is not a read: it puts the blue tick on the contact's phone, so it is limited to
  # the bot that actually serves the thread.
  def read_receipt?
    return agent_bot_serves_conversation? if agent_bot?

    show?
  end

  private

  def agent_bot_serves_conversation?
    record.assignee_agent_bot_id == user.id || user.inboxes.exists?(id: record.inbox_id)
  end

  def agent_can_view_conversation?
    inbox_access? || team_access?
  end

  def administrator?
    account_user&.administrator?
  end

  def agent_bot?
    user.is_a?(AgentBot)
  end

  def inbox_access?
    user.inboxes.where(account_id: account&.id).exists?(id: record.inbox_id)
  end

  def team_access?
    return false if record.team_id.blank?

    user.teams.where(account_id: account&.id).exists?(id: record.team_id)
  end

  def assigned_to_user?
    record.assignee_id == user.id
  end

  def participant?
    record.conversation_participants.exists?(user_id: user.id)
  end
end

ConversationPolicy.prepend_mod_with('ConversationPolicy')
