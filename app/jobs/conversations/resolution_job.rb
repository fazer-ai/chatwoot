class Conversations::ResolutionJob < ApplicationJob
  queue_as :low

  def perform(account:)
    # limiting the number of conversations to be resolved to avoid any performance issues
    resolvable_conversations = conversation_scope(account).limit(Limits::BULK_ACTIONS_LIMIT)
    resolvable_conversations.each do |conversation|
      resolve_conversation(account, conversation)
    end
  end

  private

  # Wraps the resolution side effects in a `SELECT ... FOR UPDATE` so two
  # concurrent jobs (e.g. a Sidekiq retry overlapping with the next cron
  # tick, or any other reason the same conversation appears in two job
  # scopes) can't both fire the template + label + status flip. The second
  # job into the lock re-reads the status from the DB and bails when it's
  # already resolved, instead of trusting the cached state from the outer
  # `find_each` query that picked the conversation up.
  def resolve_conversation(account, conversation)
    conversation.with_lock do
      next unless conversation.open?

      # send message from bot that conversation has been resolved
      # do this if account.auto_resolve_message is set
      ::MessageTemplates::Template::AutoResolve.new(conversation: conversation).perform if account.auto_resolve_message.present?
      conversation.add_labels(account.auto_resolve_label) if account.auto_resolve_label.present?
      conversation.toggle_status
    end
  end

  def conversation_scope(account)
    if account.auto_resolve_ignore_waiting
      account.conversations.resolvable_not_waiting(account.auto_resolve_after)
    else
      account.conversations.resolvable_all(account.auto_resolve_after)
    end
  end
end
