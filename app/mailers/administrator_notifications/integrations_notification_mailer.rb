class AdministratorNotifications::IntegrationsNotificationMailer < AdministratorNotifications::BaseMailer
  def slack_disconnect
    subject = I18n.t('mailer.administrator_notifications.integrations_notifications.slack_disconnect.subject')
    action_url = settings_url('integrations/slack')
    send_notification(subject, action_url: action_url)
  end

  def dialogflow_disconnect
    subject = I18n.t('mailer.administrator_notifications.integrations_notifications.dialogflow_disconnect.subject')
    send_notification(subject)
  end
end
