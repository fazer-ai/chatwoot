module Enterprise::AgentNotifications::ConversationNotificationsMailer
  def sla_missed_first_response(conversation, agent, sla_policy)
    return unless smtp_config_set_or_development?

    @agent = agent
    @conversation = conversation
    @sla_policy = sla_policy
    subject = I18n.t('mailer.agent_notifications.sla_missed_first_response.subject', conversation_id: @conversation.display_id)
    @action_url = app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)
    send_mail_with_liquid(to: @agent.email, subject: subject) and return
  end

  def sla_missed_next_response(conversation, agent, sla_policy)
    return unless smtp_config_set_or_development?

    @agent = agent
    @conversation = conversation
    @sla_policy = sla_policy
    @action_url = app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)
    subject = I18n.t('mailer.agent_notifications.sla_missed_next_response.subject', conversation_id: @conversation.display_id)
    send_mail_with_liquid(to: @agent.email, subject: subject) and return
  end

  def sla_missed_resolution(conversation, agent, sla_policy)
    return unless smtp_config_set_or_development?

    @agent = agent
    @conversation = conversation
    @sla_policy = sla_policy
    @action_url = app_account_conversation_url(account_id: @conversation.account_id, id: @conversation.display_id)
    subject = I18n.t('mailer.agent_notifications.sla_missed_resolution.subject', conversation_id: @conversation.display_id)
    send_mail_with_liquid(to: @agent.email, subject: subject) and return
  end

  def liquid_droppables
    super.merge({
                  sla_policy: @sla_policy
                })
  end
end
