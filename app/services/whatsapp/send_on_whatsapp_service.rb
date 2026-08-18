class Whatsapp::SendOnWhatsappService < Base::SendOnChannelService
  include BaileysHelper

  private

  def channel_class
    Channel::Whatsapp
  end

  def perform_reply
    return send_template_message if template_params.present?

    if message.conversation.can_reply?
      return channel.provider == 'baileys' ? send_baileys_session_message : send_session_message
    end

    message.update_under_lock!(status: :failed, external_error: I18n.t('errors.whatsapp.message_outside_messaging_window'))
  end

  def send_template_message
    processor = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: template_params,
      message: message
    )

    name, namespace, lang_code, processed_parameters = processor.call

    if name.blank?
      message.update_under_lock!(status: :failed, external_error: 'Template not found or invalid template name')
      return
    end

    message_id = channel.send_template(recipient_id, {
                                         name: name,
                                         namespace: namespace,
                                         lang_code: lang_code,
                                         parameters: processed_parameters
                                       }, message)
    persist_source_id(message_id)
  rescue ArgumentError, CustomExceptions::Whatsapp::MediaUploadError => e
    # Parameter validation (media URL, coupon code, media type) rejected the template, or its sample
    # media could not be uploaded. Retrying can't fix either, so surface the reason on the message
    # instead of letting the job die silently.
    message.update_under_lock!(status: :failed, external_error: e.message)
  end

  def send_baileys_session_message
    validate_announcement_mode!
    with_baileys_channel_lock_on_outgoing_message(channel.id) do
      # Waiting on the channel lock can take minutes when the inbox is busy, so re-check right before
      # hitting the provider: the agent may have deleted the message while this job was queued.
      next if deleted_in_database?

      send_session_message
    end
  end

  def validate_announcement_mode!
    return unless conversation.contact.group_type_group?
    return unless conversation.contact.additional_attributes&.dig('announce') == true
    return if inbox_admin_in_group?

    message.update_under_lock!(status: :failed, external_error: 'Only administrators are allowed to send messages in this group')
    raise StandardError, 'Only admins can send messages in this group'
  end

  def inbox_admin_in_group?
    inbox_phone = channel.phone_number&.gsub(/[^\d]/, '')
    return false if inbox_phone.blank?

    admin_phones = conversation.contact.group_memberships.active.where(role: :admin)
                               .includes(:contact).filter_map { |m| m.contact.phone_number&.gsub(/[^\d]/, '') }

    admin_phones.any? { |phone| phones_match?(inbox_phone, phone) }
  end

  def phones_match?(phone_a, phone_b)
    return false if phone_a.blank? || phone_b.blank?

    phone_a == phone_b || (phone_a.length >= 8 && phone_b.length >= 8 && phone_a[-8..] == phone_b[-8..])
  end

  def send_session_message
    message_id = channel.send_message(recipient_id, message)
    persist_source_id(message_id)
  end

  # The message may have been deleted while this send was in flight — the DELETE endpoint found no
  # `source_id` to revoke and skipped the provider, so it is on us to revoke it now that we have one.
  # The flag is read from the same locked read the write took, which is also where the DELETE endpoint
  # reads the `source_id`: whoever enters that critical section first leaves the revocation to the
  # other side, so the provider delete is enqueued exactly once.
  def persist_source_id(message_id)
    return if message_id.blank?

    # Only whoever assigns the id owns the revoke: a session inbox has a second writer of
    # this column, the echo of our own send, and both of them seeing `deleted` would ask
    # the provider to revoke the same message twice. The assignment and that decision
    # share one row lock, which is what makes the answer unambiguous.
    return unless Whatsapp::Session::Outbound::SourceIdReservation.assign(message, { source_id: message_id })

    ::Messages::DeleteOnChannelJob.perform_later(message.id)
  end

  # Reads the flag straight from the database: a full `message.reload` would also drop the cached
  # conversation/inbox/channel chain this service leans on.
  def deleted_in_database?
    Message.select(:id, :content_attributes).find_by(id: message.id)&.deleted?
  end

  def recipient_id
    return message.conversation.contact_inbox.source_id unless channel.session_family?

    # NOTE: `identifier` must be in the WhatsApp LID format
    message.conversation.contact.phone_number&.gsub(/[^\d]/, '') || message.conversation.contact.identifier
  end

  def template_params
    message.additional_attributes && message.additional_attributes['template_params']
  end
end
