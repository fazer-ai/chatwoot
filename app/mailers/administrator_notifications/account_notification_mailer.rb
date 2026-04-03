class AdministratorNotifications::AccountNotificationMailer < AdministratorNotifications::BaseMailer
  def account_deletion_user_initiated(account, reason)
    brand_name = GlobalConfig.get('BRAND_NAME')['BRAND_NAME'].presence || 'Chatwoot'
    subject = I18n.t('mailer.administrator_notifications.account_notifications.account_deletion_user_initiated.subject', brand_name: brand_name)
    action_url = settings_url('general')
    meta = {
      'account_name' => account.name,
      'deletion_date' => format_deletion_date(account.custom_attributes['marked_for_deletion_at']),
      'reason' => reason
    }

    send_notification(subject, action_url: action_url, meta: meta)
  end

  def account_deletion_for_inactivity(account, reason)
    brand_name = GlobalConfig.get('BRAND_NAME')['BRAND_NAME'].presence || 'Chatwoot'
    subject = I18n.t('mailer.administrator_notifications.account_notifications.account_deletion_for_inactivity.subject', brand_name: brand_name)
    action_url = settings_url('general')
    meta = {
      'account_name' => account.name,
      'deletion_date' => format_deletion_date(account.custom_attributes['marked_for_deletion_at']),
      'reason' => reason
    }

    send_notification(subject, action_url: action_url, meta: meta)
  end

  def contact_import_complete(resource)
    subject = I18n.t('mailer.administrator_notifications.account_notifications.contact_import_complete.subject')

    action_url = if resource.failed_records.attached?
                   Rails.application.routes.url_helpers.rails_blob_url(resource.failed_records)
                 else
                   "#{ENV.fetch('FRONTEND_URL', nil)}/app/accounts/#{resource.account.id}/contacts"
                 end

    meta = {
      'failed_contacts' => resource.total_records - resource.processed_records,
      'imported_contacts' => resource.processed_records
    }

    send_notification(subject, action_url: action_url, meta: meta)
  end

  def contact_import_failed
    subject = I18n.t('mailer.administrator_notifications.account_notifications.contact_import_failed.subject')
    send_notification(subject)
  end

  def contact_export_complete(file_url, email_to)
    subject = I18n.t('mailer.administrator_notifications.account_notifications.contact_export_complete.subject')
    send_notification(subject, to: email_to, action_url: file_url)
  end

  def automation_rule_disabled(rule)
    subject = I18n.t('mailer.administrator_notifications.account_notifications.automation_rule_disabled.subject')
    action_url = settings_url('automation/list')
    meta = { 'rule_name' => rule.name }

    send_notification(subject, action_url: action_url, meta: meta)
  end

  private

  def format_deletion_date(deletion_date_str)
    return 'Unknown' if deletion_date_str.blank?

    Time.zone.parse(deletion_date_str).strftime('%B %d, %Y')
  rescue StandardError
    'Unknown'
  end
end
