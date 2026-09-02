class AgentBotListener < BaseListener
  def conversation_resolved(event)
    conversation = extract_conversation_and_account(event)[0]
    payload = conversation.webhook_data.merge(event: __method__.to_s)
    deliver(conversation.inbox, conversation, payload)
  end

  def conversation_opened(event)
    conversation = extract_conversation_and_account(event)[0]
    payload = conversation.webhook_data.merge(event: __method__.to_s)
    deliver(conversation.inbox, conversation, payload)
  end

  def conversation_status_changed(event)
    conversation = extract_conversation_and_account(event)[0]
    changed_attributes = extract_changed_attributes(event)
    payload = conversation.webhook_data.merge(event: __method__.to_s, changed_attributes: changed_attributes)
    deliver(conversation.inbox, conversation, payload)
  end

  def conversation_updated(event)
    conversation = extract_conversation_and_account(event)[0]
    changed_attributes = extract_changed_attributes(event)
    payload = conversation.webhook_data.merge(event: __method__.to_s, changed_attributes: changed_attributes)
    deliver(conversation.inbox, conversation, payload)
  end

  def message_created(event)
    message = extract_message_and_account(event)[0]
    return unless message.webhook_sendable?

    deliver(message.inbox, message.conversation, message.webhook_data.merge(event: __method__.to_s))
  end

  def message_updated(event)
    message = extract_message_and_account(event)[0]
    return unless message.webhook_sendable?

    deliver(message.inbox, message.conversation, message.webhook_data.merge(event: __method__.to_s))
  end

  def webwidget_triggered(event)
    contact_inbox = event.data[:contact_inbox]
    payload = contact_inbox.webhook_data.merge(event: __method__.to_s)
    payload[:event_info] = event.data[:event_info]
    deliver(contact_inbox.inbox, nil, payload)
  end

  private

  # The responders first (the conversation's own bot and the inbox's), then the observers the
  # responders did not already cover. Each role travels under its own webhook type, which is what
  # keeps a failing observer from handing a conversation it does not own to a human
  # (Webhooks::Trigger#handle_error, Webhooks::ErrorHandler). See AgentBotObserver.
  def deliver(inbox, conversation, payload)
    responders = agent_bots_for(inbox, conversation)
    responders.each { |agent_bot| process_webhook_bot_event(agent_bot, payload, :agent_bot_webhook) }
    (observer_agent_bots_for(inbox) - responders).each do |agent_bot|
      process_webhook_bot_event(agent_bot, payload, :agent_bot_observer_webhook)
    end
  end

  def agent_bots_for(inbox, conversation = nil)
    bots = []
    bots << conversation.assignee_agent_bot if conversation&.assignee_agent_bot.present?
    inbox_bot = active_inbox_agent_bot(inbox)
    bots << inbox_bot if inbox_bot.present?
    bots.compact.uniq
  end

  def active_inbox_agent_bot(inbox)
    return unless inbox.agent_bot_inbox&.active?

    inbox.agent_bot
  end

  def observer_agent_bots_for(inbox)
    inbox.agent_bot_observers.active.includes(:agent_bot).map(&:agent_bot)
  end

  def process_webhook_bot_event(agent_bot, payload, webhook_type)
    # Only webhook bots are supported
    return if agent_bot.outgoing_url.blank?

    AgentBots::WebhookJob.perform_later(agent_bot.outgoing_url, payload, webhook_type,
                                        secret: agent_bot.secret, delivery_id: SecureRandom.uuid)
  end
end
