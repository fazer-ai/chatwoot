# A customer's message that reopens a resolved conversation on an inbox with an active agent
# bot sets it pending, the status the bot answers. The bot becomes its owner as well, as it is
# on a conversation's creation (Conversation#set_active_bot_conversation), instead of the
# person who held it before the resolve: a conversation has one owner, and while a person
# owns it the bot does not answer. The resolve already credited that person in the reports.
module ReopenAgentBotHandler
  extend ActiveSupport::Concern

  included do
    # Included after ReopenTeamAssigneeHandler and before AssignmentHandler, so the assignment
    # callbacks of this same save see the owner this settles.
    before_save :hand_reopened_conversation_to_agent_bot, if: -> { @reopen_agent_bot_judged }
  end

  # Called by the customer's message right before the status save that reopens the
  # conversation; the decision is taken inside that save, under the row lock.
  def hand_reopen_to_agent_bot
    @reopen_agent_bot_judged = { assignee_id: assignee_id }
  end

  private

  # An agent can reassign or reopen the conversation after the message read it and before this
  # save: the bot takes it only while the row is still resolved and still held by the owner read.
  def hand_reopened_conversation_to_agent_bot
    judged = @reopen_agent_bot_judged
    @reopen_agent_bot_judged = nil
    bot_inbox = inbox.agent_bot_inbox
    return unless bot_inbox&.active?

    owner_id, persisted_status = self.class.lock.where(id: id).pick(:assignee_id, :status)
    return unless persisted_status == 'resolved' && owner_id == judged[:assignee_id]

    self.assignee = nil
    self.ai_assignee = bot_inbox.agent_bot
  end
end
