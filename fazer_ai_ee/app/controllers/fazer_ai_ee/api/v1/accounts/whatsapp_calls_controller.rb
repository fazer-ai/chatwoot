# Calls placed through a paired phone (the connector), plus the business-hours rule on the
# caller's claim. `create_outbound_call` is copied whole because both changes sit in the
# middle of it; upstream_overrides_spec.rb fingerprints the original and fails when upstream
# changes it.
module FazerAiEe::Api::V1::Accounts::WhatsappCallsController
  def self.prepended(base)
    # A paired phone dials through the connector, which refuses a call the way Meta's API
    # does, only in its own terms: a number not on WhatsApp, a session that is not connected.
    base.rescue_from Whatsapp::Session::Errors::Error, with: :render_call_error
  end

  # The connector can report the pickup, or the end, of a call before this request got to
  # record it; what it said is applied once this tab knows the call.
  def initiate
    super
    reconcile_connector_call if @call && @inbox.channel.session_provider?
  end

  private

  def reconcile_connector_call
    Whatsapp::ConnectorCallReconcileJob.set(wait: Whatsapp::ConnectorCallReconcileJob::DELAY).perform_later(@call.id)
  end

  # A group's source id is not a person to dial, and WhatsApp has no group call to place.
  def ensure_call_recipient
    return render_could_not_create_error(I18n.t('errors.whatsapp.calls.group_not_supported')) if @conversation&.group_type_group?

    super
  end

  def create_outbound_call
    # A reused thread unassigned at click time is claimed for the caller (wins over auto-assignment); a
    # fresh thread (@conversation nil until the dial succeeds) is created already assigned to the caller.
    claim_for_caller = @conversation.present? && @conversation.assigned_entity.nil?

    result = provider_service.initiate_call(call_recipient, params[:sdp_offer], **connector_call_context)
    provider_call_id = result.dig('calls', 0, 'id') || result['call_id']

    @conversation = open_conversation!
    claim_conversation_for_caller if claim_for_caller

    create_call_record(provider_call_id)
  end

  # Runs after the dial, which cannot be undone: an inbox that holds assignment while closed keeps
  # the call and stays unassigned, including when it closes while the row lock is awaited and the
  # save itself is refused.
  def claim_conversation_for_caller
    return if @conversation.inbox.assignment_closed?

    @conversation.with_lock { @conversation.update!(assignee: Current.user) }
  rescue CustomExceptions::Conversation::OutsideWorkingHours
    @conversation.restore_attributes
  end

  # The connector dials numbers only. The contact panel hands over the contact's number,
  # which is one; a conversation hands over its bare-digit source id, which the contact
  # called is what tells apart from a LID's.
  def connector_call_context
    return {} unless @inbox.channel.session_provider?

    { contact: @contact, number: params[:conversation_id].blank? }
  end
end
