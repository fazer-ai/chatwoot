# `perform!` is copied whole because the claim sits in the middle of upstream's transaction;
# upstream_overrides_spec.rb fingerprints the original and fails when upstream changes it.
module FazerAiEe::Voice::OutboundCallBuilder
  def perform!
    raise ArgumentError, 'Contact phone number required' if contact.phone_number.blank?
    raise ArgumentError, 'Agent required' if user.blank?

    # Claim for the caller if a reused conversation is unassigned at trigger time; wins over auto-assignment.
    # New conversations set the assignee at creation instead (see create_conversation!).
    claim_for_caller = @existing_conversation && @existing_conversation.assigned_entity.nil?

    ActiveRecord::Base.transaction do
      contact_inbox = ensure_contact_inbox!
      conversation = @existing_conversation || create_conversation!(contact_inbox)
      # Dial before locking so the Twilio round-trip doesn't hold the conversation row lock.
      call_sid = initiate_call!
      claim_reused_conversation! if claim_for_caller
      call = create_call!(conversation, call_sid)
      message = Voice::CallMessageBuilder.new(call).perform!
      call.update!(message_id: message.id)
      # Status callbacks that arrived before this commit found no call to update
      ActiveRecord.after_all_transactions_commit { Voice::SyncProviderStatusJob.perform_later(call.id) }
      call
    end
  end

  private

  # Runs after the dial, which cannot be undone: an inbox that holds assignment while closed keeps
  # the call and stays unassigned, including when it closes while the row lock is awaited and the
  # save itself is refused.
  def claim_reused_conversation!
    return if @existing_conversation.inbox.assignment_closed?

    @existing_conversation.lock!
    @existing_conversation.update!(assignee: user)
  rescue CustomExceptions::Conversation::OutsideWorkingHours
    @existing_conversation.restore_attributes
  end
end
