class Email::SendOnEmailService < Base::SendOnChannelService
  # Raised when delivery failed for a reason that says nothing about the recipient:
  # a 4xx from the SMTP server, a timeout, a dropped connection. Wrapped in a type of
  # our own instead of retrying the underlying errors directly, because those classes
  # also surface from other channels' HTTP clients, and a `retry_on` on them would
  # silently change how every other channel behaves on a network blip.
  class TransientDeliveryError < StandardError; end

  # RFC 5321 reserves 4xx for "the command was not accepted, try again later", and a
  # timeout or reset connection carries no verdict at all. Net::SMTPServerBusy is the
  # 4xx one -- it covers Gmail's 451 throttling, which is what we actually hit.
  TRANSIENT_ERRORS = [
    Net::SMTPServerBusy,
    Net::OpenTimeout,
    Net::ReadTimeout,
    Errno::ECONNRESET,
    Errno::ECONNREFUSED,
    Errno::EHOSTUNREACH,
    Errno::ENETUNREACH,
    SocketError,
    OpenSSL::SSL::SSLError
  ].freeze

  private

  def channel_class
    Channel::Email
  end

  def perform_reply # rubocop:disable Metrics/AbcSize
    return unless message.email_notifiable_message?

    mail = ConversationReplyMailer.with(account: message.account).email_reply(message)
    raise "Email could not be prepared for message #{message.id}" if mail.nil?

    reply_mail = mail.deliver_now
    raise "Email delivery returned nil for message #{message.id}" if reply_mail.nil?

    Rails.logger.info("Email message #{message.id} sent with source_id: #{reply_mail.message_id}")
    message.update!(source_id: reply_mail.message_id)
  rescue *TRANSIENT_ERRORS => e
    # Deliberately not marked failed and not reported here: the job retries, and only
    # the exhausted-retries handler decides the message is really lost. Reporting on
    # every attempt would page us for a blip the retry already absorbed.
    Rails.logger.warn("Transient email delivery failure for message #{message.id}: #{e.class}: #{e.message}")
    raise TransientDeliveryError, "#{e.class}: #{e.message}"
  rescue StandardError => e
    ChatwootExceptionTracker.new(e, account: message.account).capture_exception
    Messages::StatusUpdateService.new(message, 'failed', e.message).perform
  end
end
