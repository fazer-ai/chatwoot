class MessagePolicy < ApplicationPolicy
  def destroy?
    return true unless deletion_blocked_for_agents?

    administrator? || agent_bot? || custom_role?
  end

  private

  def deletion_blocked_for_agents?
    account&.disable_agent_message_deletion.present?
  end

  def administrator?
    account_user&.administrator?
  end

  def agent_bot?
    user.is_a?(AgentBot)
  end

  def custom_role?
    account_user&.custom_role_id.present?
  end
end

MessagePolicy.prepend_mod_with('MessagePolicy')
