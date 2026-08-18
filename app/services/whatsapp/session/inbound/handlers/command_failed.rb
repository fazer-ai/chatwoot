# A fire-and-forget command could not be executed. The only one with something to show
# for it is a send: its message is marked failed so the agent sees it did not go out.
class Whatsapp::Session::Inbound::Handlers::CommandFailed < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    Rails.logger.warn(
      "[WHATSAPP SESSION] command #{payload.command_type} failed on inbox #{inbox.id}: #{payload.error&.code}"
    )
    message = pending_message
    return :ignored if message.nil?

    inbound::StatusTransition.apply(message, 'failed', error: payload.error) ? :handled : :ignored
  end

  private

  # The send reserved its WhatsApp id before dispatching, so the failed command points
  # at a message that may not carry that id as source_id yet.
  def pending_message
    return if payload.message_id.blank?

    find_message(payload.message_id) || inbox.messages.where(
      "(content_attributes#>>'{}')::jsonb->>'pending_source_id' = ?", payload.message_id
    ).first
  end
end
