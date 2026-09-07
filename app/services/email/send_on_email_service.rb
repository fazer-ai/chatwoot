class Email::SendOnEmailService < Base::SendOnChannelService
  # Raised when delivery failed for a reason that says nothing about the recipient:
  # a 4xx from the SMTP server, a timeout, a dropped connection. Wrapped in a type of
  # our own instead of retrying the underlying errors directly, because those classes
  # also surface from other channels' HTTP clients, and a `retry_on` on them would
  # silently change how every other channel behaves on a network blip.
  class TransientDeliveryError < StandardError; end

  # Only failures that carry a verdict belong here, because a retry re-sends the email
  # and `source_id` -- the one proof a copy already left -- is written after delivery
  # returns. So the test is not "is this error temporary?" but "does it prove the
  # server did NOT take the message?".
  #
  # These prove it. A 4xx is the server saying so in words (RFC 5321: "not accepted,
  # try again later"), and Net::SMTPServerBusy is the class Gmail's 451 throttling
  # raises, which is the failure we actually hit. The rest fail while connecting or
  # while writing, both before the server can have the message.
  #
  # Net::SMTPServerBusy only earns its place here because of the QUIT patch in
  # config/initializers/monkey_patches/net_smtp_quit.rb. Without it net-smtp raises the
  # very same class for a 4xx answered to QUIT, which arrives AFTER the message was
  # accepted -- and retrying that is a duplicate. Do not drop that patch.
  #
  # Net::ReadTimeout, Errno::ECONNRESET and OpenSSL::SSL::SSLError are deliberately
  # NOT here. They read as network blips, but each can also surface on the read of the
  # 250 that follows the DATA terminator -- the message is already queued at the
  # server and only the answer was lost. Retrying there sends the customer a second
  # copy, and with five attempts, up to five. Ruby's Net::SMTP does not say which
  # command was in flight, so the ambiguity cannot be resolved from here. They fall
  # through to the handler below and mark the message failed, which is visible in the
  # UI and recoverable by a human -- unlike a duplicate already in the customer's inbox.
  TRANSIENT_ERRORS = [
    Net::SMTPServerBusy,
    Net::OpenTimeout,
    Errno::ECONNREFUSED,
    Errno::EHOSTUNREACH,
    Errno::ENETUNREACH,
    SocketError
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
