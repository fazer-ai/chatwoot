class Conversations::AssignmentService
  def initialize(conversation:, assignee_id:, assignee_type: nil)
    @conversation = conversation
    @assignee_id = assignee_id
    @assignee_type = assignee_type
  end

  def perform
    agent_bot_assignment? ? assign_agent_bot : assign_agent
  end

  private

  attr_reader :conversation, :assignee_id, :assignee_type

  def assign_agent
    conversation.with_lock do
      if open_on_assignment? && conversation.pending?
        conversation.status = :open
        conversation.waiting_since = Time.current if conversation.waiting_since.blank?
      end
      conversation.assignee = assignee
      conversation.ai_assignee = nil
      conversation.save!
    end
    assignee
  end

  def assign_agent_bot
    assign_ai_assignee(agent_bot)
  end

  def open_on_assignment?
    assignee.present? && conversation.ai_assignee_type.present?
  end

  def assign_ai_assignee(ai_assignee)
    return unless ai_assignee

    conversation.with_lock do
      conversation.assignee = nil
      conversation.ai_assignee = ai_assignee
      conversation.status = :pending
      conversation.save!
    end
    ai_assignee
  end

  def assignee
    @assignee ||= conversation.account.users.find_by(id: assignee_id)
  end

  # Only the bot serving the conversation's inbox, the rule the Captain assistant already follows
  # (Enterprise::Conversations::AssignmentService#captain_assistant). Any other bot of the account
  # would take the conversation out of the team's queues without ever answering it (#721).
  def agent_bot
    bot_inbox = conversation.inbox.agent_bot_inbox
    bot_inbox.agent_bot if bot_inbox&.active? && bot_inbox.agent_bot_id == assignee_id.to_i
  end

  def agent_bot_assignment?
    assignee_type.to_s == 'AgentBot'
  end
end

Conversations::AssignmentService.prepend_mod_with('Conversations::AssignmentService')
