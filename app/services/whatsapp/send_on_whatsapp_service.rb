class Whatsapp::SendOnWhatsappService < Base::SendOnChannelService
  include BaileysHelper

  private

  def channel_class
    Channel::Whatsapp
  end

  def perform_reply
    # Baileys uses the Web/multi-device protocol — there is no 24h customer
    # service window and no template gating. Routing through the template
    # path used to result in a no-op (Baileys' send_template returns nil),
    # leaving the message forever in "sent" with no source_id. Always use
    # the session path so the warm-up + retry from the Baileys send flow
    # gets a chance to recover cold conversations.
    if channel.provider == 'baileys'
      send_baileys_session_message
    elsif template_params.present? || !message.conversation.can_reply?
      send_template_message
    else
      send_session_message
    end
  end

  def send_template_message
    processor = Whatsapp::TemplateProcessorService.new(
      channel: channel,
      template_params: template_params,
      message: message
    )

    name, namespace, lang_code, processed_parameters = processor.call

    if name.blank?
      message.update!(status: :failed, external_error: 'Template not found or invalid template name')
      return
    end

    message_id = channel.send_template(recipient_id, {
                                         name: name,
                                         namespace: namespace,
                                         lang_code: lang_code,
                                         parameters: processed_parameters
                                       }, message)
    message.update!(source_id: message_id) if message_id.present?
  end

  def send_baileys_session_message
    validate_announcement_mode!
    with_baileys_channel_lock_on_outgoing_message(channel.id) { send_session_message }
  end

  def validate_announcement_mode!
    return unless conversation.contact.group_type_group?
    return unless conversation.contact.additional_attributes&.dig('announce') == true
    return if inbox_admin_in_group?

    message.update!(status: :failed, external_error: 'Only administrators are allowed to send messages in this group')
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

    message_id = retry_send_after_warmup if message_id.blank? && channel.provider == 'baileys'

    if message_id.present?
      message.update!(source_id: message_id)
    elsif message.reload.external_error.blank?
      # Baileys' Signal session can fail to re-establish silently for cold
      # conversations (e.g., gap > 24h since the last message), in which case
      # sendMessage returns no id and no error. Leaving the message in the
      # default "sent" status hides this from the operator; surfacing it as
      # failed makes the red marker show up so they can retry.
      #
      # Only kick in when no provider-specific error message has been saved
      # yet — Cloud / Z-API / 360Dialog already write a detailed error via
      # `handle_error` and we'd be overwriting it with a generic message.
      message.update!(status: :failed, external_error: 'Provider did not return a message id')
    end
  end

  # When Baileys returns no id, the most common cause is a cold Signal session
  # that didn't re-establish in time. on_whatsapp + presence_subscribe trigger
  # a fresh handshake; the short sleep lets it settle before the retry.
  # baileys-api's idempotency layer releases the lock (without caching) when
  # the inner send returned null, so the retry with the same key actually
  # re-executes instead of returning the cached null.
  def retry_send_after_warmup
    warm_session
    Rails.logger.info("[whatsapp-send] retrying after warm-up message_id=#{message.id}")
    channel.send_message(recipient_id, message)
  end

  def warm_session
    jid = recipient_id.include?('@') ? recipient_id : "#{recipient_id}@s.whatsapp.net"
    channel.on_whatsapp(jid)
    channel.presence_subscribe([jid])
    sleep 1.0
  rescue StandardError => e
    Rails.logger.warn("[whatsapp-send] warm-up failed conv=#{message.conversation_id} err=#{e.message}")
  end

  def recipient_id
    return message.conversation.contact_inbox.source_id unless %w[baileys zapi].include?(channel.provider)

    contact = message.conversation.contact
    # Prefer LID when present: phone-derived JIDs only route when the number
    # matches the format the WhatsApp account was originally registered with,
    # which for pre-2012 Brazilian accounts is 12 digits. After we started
    # normalizing inbound phones to 13d, those JIDs stopped routing — LID
    # routing bypasses the format mismatch.
    return contact.identifier if contact.identifier&.end_with?('@lid')

    contact.phone_number&.gsub(/[^\d]/, '') || contact.identifier
  end

  def template_params
    message.additional_attributes && message.additional_attributes['template_params']
  end
end
