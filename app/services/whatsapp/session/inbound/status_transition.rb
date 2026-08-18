# The single place that decides whether a delivery receipt may move a message forward.
#
# The legacy layer had this rule twice (messages.update and message-receipt.update) and
# they had already drifted apart. Receipts can arrive out of order, so the rule is
# monotonic: a message never goes back to a weaker status, and `read` is terminal.
module Whatsapp::Session::Inbound::StatusTransition
  # `played` is a voice note being listened to, which Chatwoot has no column for and
  # which always implies read.
  RECEIPTS = { 'delivered' => 'delivered', 'read' => 'read', 'played' => 'read', 'failed' => 'failed' }.freeze
  RANK = { 'sent' => 0, 'delivered' => 1, 'read' => 2 }.freeze
  # Nothing moves a message out of these. A failure reported after the message was
  # delivered or read describes an earlier attempt, not the message coming undone:
  # either status is proof it arrived. A second failure has nothing left to say.
  TERMINAL = %w[delivered read failed].freeze

  module_function

  # Returns true when the message was updated.
  #
  # Checked and written under the row lock. Two receipts for the same message can be
  # processed at once, and reading the status outside the lock lets both pass the check
  # against the same old value: the slower `delivered` write then lands on top of `read`
  # and walks the message backwards, which is exactly what this rule exists to prevent.
  def apply(message, receipt_type, error: nil)
    status = RECEIPTS[receipt_type.to_s]
    return false if status.blank?

    message.with_lock do
      next false unless allowed?(message.status, status)

      message.update!(failure_attributes(status, error))
      true
    end
  end

  def failure_attributes(status, error)
    return { status: status } unless status == 'failed'

    { status: :failed, external_error: error_message(error) }
  end

  def allowed?(current, new_status)
    return false if current.in?(TERMINAL) && new_status == 'failed'
    return false if current.in?(%w[read failed])
    return true if new_status == 'failed'

    RANK.fetch(new_status, -1) > RANK.fetch(current, -1)
  end

  def error_message(error)
    return if error.blank?
    return error if error.is_a?(String)

    [error.message.presence, error.code.presence].compact.join(' ').presence
  end
end
