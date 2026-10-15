# Sends again a refusal or a hang-up the connector could not carry out. The call was
# already closed here when the command went out, so nothing else would: a refusal that
# expired behind queued media sends leaves the caller's phone ringing, and a hang-up that
# hit its runtime ceiling leaves the call connected until WhatsApp times it out.
#
# Only while a retry can answer differently (`retryable?`), and a few times: a refusal that
# lands after the call stopped ringing refuses nothing, and the connector drops a hang-up
# for a call that already ended, so a spent budget costs nothing that was still owed.
class Whatsapp::CallCommandRetryJob < ApplicationJob
  queue_as :high

  WAITS = [5.seconds, 30.seconds, 2.minutes].freeze

  # A Redis that is down, or a connector fleet speaking another protocol: the frame was not
  # written, so a later attempt can still deliver it.
  retry_on Whatsapp::Session::Errors::ProviderUnavailable, wait: :polynomially_longer, attempts: 5

  # Schedules the next attempt of the command `remembered` describes. Answers whether it did.
  def self.consider(inbox, command_type, error, remembered)
    return false unless error.present? && error.to_exception.retryable?

    schedule(inbox, command_type, remembered.call_id, remembered.from, remembered.attempt + 1)
  end

  def self.schedule(inbox, command_type, call_id, from, attempt)
    wait = WAITS[attempt - 1]
    if wait.nil?
      Rails.logger.warn("[WHATSAPP CALL] #{command_type} for call #{call_id} failed #{attempt} times on inbox #{inbox.id}; giving up")
      return false
    end

    set(wait: wait).perform_later(inbox.id, command_type, call_id, from, attempt)
    true
  end

  def perform(inbox_id, command_type, call_id, from, attempt)
    inbox = Inbox.find_by(id: inbox_id)
    return if inbox.nil? || !inbox.channel.try(:session_provider?)

    provider = inbox.channel.provider_service
    sent = if command_type == 'call.reject'
             provider.reject_call(call_id, from: from, attempt: attempt)
           else
             provider.terminate_call(call_id, attempt: attempt)
           end
    # The connector refused it before this could write down which call it was for, so its
    # failure was dropped unread and only this side knows the attempt did not go through.
    self.class.schedule(inbox, command_type, call_id, from, attempt + 1) unless sent
  rescue Whatsapp::Session::Errors::Error => e
    raise if e.retryable?

    Rails.logger.warn("[WHATSAPP CALL] #{command_type} for call #{call_id} not sent again on inbox #{inbox_id}: #{e.message}")
  end
end
