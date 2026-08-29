# When a mail was sent, answered the same way for everyone who asks.
#
# Two callers need it and they must not disagree: the backfill reads it off the header to
# decide whether to fetch a message's attachments, and the importer reads it off the whole
# mail to date the row. Derived separately, a message with no usable `Date` would be
# stripped of its attachments by the first and then dated by the second into a window where
# the cutoff would have kept them -- and the attachments are already gone by then.
module Import::Email::Timestamp
  module_function

  def of(mail)
    sent_at(mail) || received_at(mail)
  end

  # `Mail` is not consistent about how it refuses a bad `Date`: an unreadable field comes
  # back as the raw String, whose `to_time` is ActiveSupport's and answers nil, and one that
  # parses into an impossible time raises from the reader itself. Both mean the same thing
  # here, and neither is a reason to count the message as an error and retry it forever.
  def sent_at(mail)
    date = mail.date
    date.to_time if date.respond_to?(:to_time)
  rescue StandardError
    nil
  end

  # Every relay that touched the mail stamped a line on the way, and the oldest of those is
  # the closest thing a message with no usable `Date` has to a send time.
  def received_at(mail)
    Array(mail.received).filter_map { |field| field.date_time&.to_time }.min
  rescue StandardError
    nil
  end
end
