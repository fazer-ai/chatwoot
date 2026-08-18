# A message was deleted for everyone: by the contact, or from the connected phone.
#
# If the revoke somehow arrives before the message it points at, this is a no-op and
# the message is later stored without the flag. WhatsApp delivers in order, so that is
# rare and accepted; persisting pending revokes would need its own state.
class Whatsapp::Session::Inbound::Handlers::MessageRevoked < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    target = find_message(payload.message_id)
    return :ignored if target.nil?

    payload.by_self? ? revoke_by_self(target) : revoke_by_contact(target)
  end

  private

  # Deleted from the connected phone: same outcome as deleting it from Chatwoot, which
  # is also what the echo of a Chatwoot deletion looks like (hence the guard).
  def revoke_by_self(target)
    return :ignored if target.deleted?

    target.update!(content: '', content_attributes: target.content_attributes.merge('deleted' => true))
    :handled
  end

  # The contact deleted it: keep the stored content and only flag it, so the agent can
  # still read what was said while the UI marks it as deleted.
  def revoke_by_contact(target)
    return :ignored if target.deleted_by_contact

    target.update!(deleted_by_contact: true)
    :handled
  end
end
