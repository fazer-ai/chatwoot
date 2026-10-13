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
    after_rollback { @reopen_agent_bot_handoff = nil }
  end

  # The handoff unassigns the person on the customer's behalf, so it is not a takeover, whoever is
  # in Current.user (an API inbox can post the customer's message with an agent token).
  def reopen_agent_bot_handoff?
    @reopen_agent_bot_handoff.present?
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

    owner_id, persisted_status, ai_owner_id, ai_owner_type =
      self.class.lock.where(id: id).pick(:assignee_id, :status, :assignee_agent_bot_id, :ai_assignee_type)
    unless persisted_status == 'resolved' && owner_id == judged[:assignee_id]
      return adopt_persisted_ownership(owner_id, persisted_status, ai_owner_id, ai_owner_type)
    end
    # A bot already owns it (a specialist the conversation was delegated to, or the inbox's own):
    # it keeps getting the customer's messages.
    return if ai_owner_type.present?

    # The team handler of this same save may have dropped the person already; its line says so.
    @reopen_agent_bot_handoff = { assignee_name: assignee&.name, bot_name: bot_inbox.agent_bot.name }
    self.assignee = nil
    self.ai_assignee = bot_inbox.agent_bot
  end

  # Someone else changed the row first (another customer message that already handed it to the bot,
  # an agent who reassigned or reopened it). This instance still holds what the message read, and
  # the events of this save serialize it: take the owner the row has, and drop a status this save
  # would only repeat, so a stale owner is neither announced nor written.
  def adopt_persisted_ownership(owner_id, persisted_status, ai_owner_id, ai_owner_type)
    self.assignee_id = owner_id
    self.assignee_agent_bot_id = ai_owner_id
    self.ai_assignee_type = ai_owner_type
    clear_attribute_changes(%i[assignee_id assignee_agent_bot_id ai_assignee_type])
    clear_attribute_changes([:status]) if status == persisted_status
  end

  # Written in place of the bot-assignment line (AgentBotAssignment::BotAssignmentActivity), which
  # needs a user and would name the token's agent of an API inbox, who did not do it.
  def create_reopen_agent_bot_activity
    handoff = @reopen_agent_bot_handoff
    @reopen_agent_bot_handoff = nil
    return create_reopen_team_unassignment_activity if reopen_team_unassignment?
    return if handoff[:assignee_name].blank?

    content = I18n.t('conversations.activity.assignee.handed_to_agent_bot_on_reopen', **handoff, locale: account.locale)
    ::Conversations::ActivityMessageJob.perform_later(self, activity_message_params(content))
  end
end
