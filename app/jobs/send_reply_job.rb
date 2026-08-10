class SendReplyJob < ApplicationJob
  queue_as :high

  # Meta's WhatsApp Cloud API returns a small set of "please try again"
  # errors on transient hiccups (their downtime, quick rate-limit blips).
  # Retry with a bounded backoff so the operator does not have to
  # hand-retry every time Meta blips for a few seconds. Only after the
  # window is exhausted do we mark the message as failed with the last
  # error we saw.
  retry_on ::Whatsapp::Providers::TransientError,
           attempts: 3,
           wait: ->(executions) { [5, 15].fetch(executions - 1, 15).seconds } do |job, error|
    Message.find_by(id: job.arguments.first)&.update!(
      status: :failed,
      external_error: error.meta_message
    )
  end

  CHANNEL_SERVICES = {
    'Channel::TwitterProfile' => '::Twitter::SendOnTwitterService',
    'Channel::TwilioSms' => '::Twilio::SendOnTwilioService',
    'Channel::Line' => '::Line::SendOnLineService',
    'Channel::Telegram' => '::Telegram::SendOnTelegramService',
    'Channel::Whatsapp' => '::Whatsapp::SendOnWhatsappService',
    'Channel::Sms' => '::Sms::SendOnSmsService',
    'Channel::Instagram' => '::Instagram::SendOnInstagramService',
    'Channel::Tiktok' => '::Tiktok::SendOnTiktokService',
    'Channel::Email' => '::Email::SendOnEmailService',
    'Channel::WebWidget' => '::Messages::SendEmailNotificationService',
    'Channel::Api' => '::Messages::SendEmailNotificationService'
  }.freeze

  def perform(message_id)
    message = Message.find(message_id)
    channel_name = message.conversation.inbox.channel.class.to_s

    return send_on_facebook_page(message) if channel_name == 'Channel::FacebookPage'

    service_class_name = CHANNEL_SERVICES[channel_name]
    return unless service_class_name

    service_class_name.constantize.new(message: message).perform
  end

  private

  def send_on_facebook_page(message)
    if message.conversation.additional_attributes['type'] == 'instagram_direct_message'
      ::Instagram::Messenger::SendOnInstagramService.new(message: message).perform
    else
      ::Facebook::SendOnFacebookService.new(message: message).perform
    end
  end
end
