class SendReplyJob < ApplicationJob
  queue_as :high

  # Declared BEFORE the MessageAlreadyProcessing handler below on purpose. retry_on is
  # built on rescue_from, which matches handlers with reverse_each — the LAST matching
  # declaration wins — so a broad class declared last would silently shadow every
  # specific one above it.
  #
  # Everything else retryable: when the attempts run out the message must not be left
  # sitting on "sent" with a clock next to it. Nobody is watching the dead set, so an
  # exhausted job is the last chance to tell the agent it did not go.
  retry_on Whatsapp::Session::Errors::Error, wait: :polynomially_longer, attempts: 4 do |job, error|
    Rails.logger.error "SendReplyJob exhausted retries for message #{job.arguments.first}: #{error.message}"
    fail_message(job.arguments.first, error.message)
  end

  # More specific than the handler above, so it has to come after it. A 409 from
  # baileys-api means another worker holds the idempotency lock for this
  # message. Sidekiq's default backoff (roughly 15s, 30s, 90s) used to burn all three
  # retries well before that lock could clear, so the job always died in the dead set.
  # Its own attempts, with a wait longer than a bounded send takes, keep the conflict
  # from consuming the retries the real failure modes need.
  retry_on Whatsapp::Session::Errors::MessageAlreadyProcessing,
           wait: 60.seconds,
           attempts: 3 do |job, error|
    Rails.logger.error(
      "SendReplyJob gave up on message #{job.arguments.first}: still processing elsewhere (#{error.message})"
    )
    fail_message(job.arguments.first, I18n.t('errors.inboxes.channel.outgoing.still_processing'))
  end

  # Marks the message failed so the agent sees it and can resend. Through
  # StatusTransition because it owns the terminal-status rule and applies it under the
  # row lock: an attempt that timed out may still have reached WhatsApp, so a receipt
  # can mark this message delivered or read while its retries are still running out.
  # Either status is proof it arrived, and walking one back to failed here is what
  # would put a duplicate in front of the customer.
  def self.fail_message(message_id, reason)
    message = Message.find_by(id: message_id)
    return if message.blank?

    Whatsapp::Session::Inbound::StatusTransition.fail_send(message, reason)
  rescue StandardError => e
    Rails.logger.error "SendReplyJob could not mark message #{message_id} as failed: #{e.message}"
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
