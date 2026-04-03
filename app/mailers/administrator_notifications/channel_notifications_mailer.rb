class AdministratorNotifications::ChannelNotificationsMailer < AdministratorNotifications::BaseMailer
  def facebook_disconnect(inbox)
    subject = I18n.t('mailer.administrator_notifications.channel_notifications.facebook_disconnect.subject')
    send_notification(subject, action_url: inbox_url(inbox))
  end

  def instagram_disconnect(inbox)
    subject = I18n.t('mailer.administrator_notifications.channel_notifications.instagram_disconnect.subject')
    send_notification(subject, action_url: inbox_url(inbox))
  end

  def tiktok_disconnect(inbox)
    subject = 'Your TikTok connection has expired'
    send_notification(subject, action_url: inbox_url(inbox))
  end

  def whatsapp_disconnect(inbox)
    subject = I18n.t('mailer.administrator_notifications.channel_notifications.whatsapp_disconnect.subject')
    send_notification(subject, action_url: inbox_url(inbox))
  end

  def email_disconnect(inbox)
    subject = I18n.t('mailer.administrator_notifications.channel_notifications.email_disconnect.subject')
    send_notification(subject, action_url: inbox_url(inbox))
  end
end
