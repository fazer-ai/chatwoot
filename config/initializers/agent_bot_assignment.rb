# Two changes to how a conversation is handed to an agent bot (#721). Upstream is kept on purpose
# where it chose: any bot of the account can still be assigned through the API, and the assigned
# bot gets the conversation's events (AgentBotListener#agent_bots_for, chatwoot/chatwoot#12836),
# which is what delegating to a specialist bot relies on.
#
# Declared here instead of as autoloaded classes, for the reason import_guards.rb gives: a
# reloadable module handed to `prepend` is a new object after every reload. Prepended rather than
# edited in, because the four files involved are upstream's and every line there is a conflict on
# every sync.
module AgentBotAssignment
  # The assignee dropdown listed every bot of the account, so the bot answering a WhatsApp inbox was
  # one click away from an e-mail conversation it had never been set up for; in production that
  # conversation sat in pending for five days with no owner. A bot connected to another inbox is no
  # longer offered. The inbox's own active bot still is, and so are the bots connected to no inbox
  # of the account, global ones included, which is where a specialist bot lives.
  #
  # With several inboxes asked for, a bot has to pass for each of them, the rule agents already
  # follow in the same action.
  module DropdownOffersNoForeignBot
    def index
      super
      return if @agent_bots.blank?

      @agent_bots = @agent_bots.select { |agent_bot| @inboxes.all? { |inbox| offered_for?(agent_bot, inbox) } }
    end

    private

    def offered_for?(agent_bot, inbox)
      bot_inbox = inbox.agent_bot_inbox
      return true if bot_inbox&.active? && bot_inbox.agent_bot_id == agent_bot.id

      (connected_inbox_ids[agent_bot.id] || []).all?(inbox.id)
    end

    # Any status, because an inactive connection still says which inbox the bot was built for.
    def connected_inbox_ids
      @connected_inbox_ids ||= AgentBotInbox.where(account_id: Current.account.id, agent_bot_id: @agent_bots.map(&:id))
                                            .pluck(:agent_bot_id, :inbox_id)
                                            .group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
    end
  end

  # Assigning a user writes "Assigned to <agent> by <user>"; assigning a bot wrote "Conversation
  # unassigned by <user>" when it replaced a human, and nothing at all otherwise, so the change had
  # no author. It now gets the same sentence. The bot the inbox hands a new conversation is left
  # out, as nobody assigned it.
  module BotAssignmentActivity
    private

    def process_assignment_activities
      return super if saved_change_to_team_id? || !ai_assignee_handed_over?

      user_name = activity_message_owner(Current.user&.name)
      return unless user_name

      content = I18n.t('conversations.activity.assignee.assigned', assignee_name: ai_assignee.name, user_name: user_name)
      ::Conversations::ActivityMessageJob.perform_later(self, activity_message_params(content))
    end

    def ai_assignee_handed_over?
      return false if previously_new_record? || ai_assignee.blank?

      saved_change_to_assignee_agent_bot_id? || saved_change_to_ai_assignee_type?
    end
  end
end

Rails.application.config.to_prepare do
  Api::V1::Accounts::AssignableAgentsController.prepend(AgentBotAssignment::DropdownOffersNoForeignBot)
  Conversation.prepend(AgentBotAssignment::BotAssignmentActivity)
end
