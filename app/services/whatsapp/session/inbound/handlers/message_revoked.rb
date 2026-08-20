# A message was deleted for everyone: by the contact, or from the connected phone.
#
# A revoke that arrives before the message it points at is answered `:deferred`, which an
# unordered transport retries. Nothing is persisted in the meantime: a revoke that outlives
# the retries leaves the message on screen rather than deleting it later.
class Whatsapp::Session::Inbound::Handlers::MessageRevoked < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    targets = find_messages(payload.message_id).to_a
    return :deferred if targets.empty?

    results = targets.map { |target| payload.by_self? ? revoke_by_self(target) : revoke_by_contact(target) }
    return :ignored unless results.include?(:handled)

    inbound::ChatList.refresh(targets.first.conversation)
    :handled
  end

  private

  # Deleted from the connected phone: same outcome as deleting it from Chatwoot, which
  # is also what the echo of a Chatwoot deletion looks like (hence the guard). Same
  # outcome means the same as the messages controller produces, attachments included:
  # leaving the files behind would keep the deleted media readable through the API and
  # in storage. The reserved id survives, so a send still in flight stays matchable.
  def revoke_by_self(target)
    return :ignored if target.deleted?

    # Under the row lock: the reserved id is read out of the hash that is about to be
    # replaced, so an echo confirming a send in between would otherwise be thrown away
    # and the message could never be taken off the contact's phone.
    target.with_lock do
      next :ignored if target.deleted?

      attributes = { 'deleted' => true, 'pending_source_id' => target.pending_source_id }.compact
      target.update!(content: I18n.t('conversations.messages.deleted'), content_type: :text,
                     content_attributes: attributes)
      target.attachments.destroy_all
      :handled
    end
  end

  # The contact deleted it: keep the stored content and only flag it, so the agent can
  # still read what was said while the UI marks it as deleted.
  def revoke_by_contact(target)
    return :ignored if target.deleted_by_contact

    # `deleted_by_contact` lives in the content_attributes JSON, so writing it off a
    # stale instance rewrites the whole hash.
    target.update_under_lock!(deleted_by_contact: true)
    :handled
  end
end
