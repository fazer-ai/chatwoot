module Whatsapp::BaileysHandlers::Concerns::MessageCreationHandler
  extend ActiveSupport::Concern

  private

  def build_and_save_message(conversation:, sender:, attach_media: false)
    @message = conversation.messages.build(
      content: message_content,
      account_id: inbox.account_id,
      inbox_id: inbox.id,
      source_id: raw_message_id,
      sender: incoming? ? sender : nil,
      message_type: incoming? ? :incoming : :outgoing,
      content_attributes: build_message_content_attributes
    )

    attach_media_to_message if attach_media

    @message.save!

    inbox.channel.received_messages([@message], conversation) if incoming?

    @message
  end

  # WhatsApp delivers a reaction removal as a fresh message with empty text.
  # Our schema keeps a single Message row per (target, sender) and toggles
  # `deleted` on it, so we look up that row and mark it removed instead of
  # creating a duplicate empty Message that the chat list would have to filter.
  #
  # `fromMe` removals can come from two paths and we want both handled:
  # - Chatwoot-originated echo: the controller already toggled the row to
  #   deleted, so the active-only lookup finds nothing and this no-ops.
  # - Multi-device removal (agent un-reacts from the connected phone): the
  #   row is still active and stored sender-less outgoing, so we mark it
  #   deleted.
  # Lookup is intentionally NOT scoped to the inbound conversation: the
  # original reaction may live in an older/resolved thread, while the inbound
  # flow could have picked (or created) a different one. Find the row first,
  # then operate on its real `existing.conversation`.
  def mark_existing_reaction_as_removed(sender:)
    target_external_id = unwrap_ephemeral_message(@raw_message[:message]).dig(:reactionMessage, :key, :id)
    return if target_external_id.blank?

    existing = find_existing_reaction(sender, target_external_id)
    return if existing.nil?

    new_attrs = existing.content_attributes.merge('deleted' => true)
    existing.update!(content: '', content_attributes: new_attrs)
    target_conversation = existing.conversation
    # Refresh the chat list snapshot of `last_non_activity_message`; the cable
    # MESSAGE_UPDATED event only refreshes chat.messages on the client, so
    # without this the preview can stay pointed at the pre-removal reaction.
    # Touch updated_at so the frontend out-of-order guard can drop stale cables.
    target_conversation.update_columns(updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    target_conversation.dispatch_conversation_updated_event
    existing
  end

  def find_existing_reaction(sender, target_external_id)
    json_path = "(content_attributes#>>'{}')::jsonb"
    # Scope by inbox: the senderless outgoing branch would otherwise match any
    # reaction with the same provider message id, and two inboxes that ever
    # receive colliding WhatsApp ids would step on each other's rows.
    base = Message.where(inbox_id: inbox.id)
                  .where("#{json_path}->>'is_reaction' = 'true'")
                  .where("#{json_path}->>'in_reply_to_external_id' = ?", target_external_id)
    matches = if incoming?
                base.where(sender: sender)
              else
                # Multi-device: agent reacted via the connected phone, so the
                # local row has no agent (sender_id IS NULL) and is outgoing.
                base.where(sender_id: nil, sender_type: nil)
                    .where(message_type: Message.message_types[:outgoing])
              end
    # Active-only: when the only matches are already deleted, this returns nil
    # so the caller no-ops instead of re-deleting and bumping the conversation
    # for an echoed Chatwoot-originated removal.
    matches.where.not(content: '')
           .where("COALESCE(#{json_path}->>'deleted', 'false') != 'true'")
           .reorder(created_at: :desc)
           .first
  end

  def build_message_content_attributes
    type = message_type
    msg = unwrap_ephemeral_message(@raw_message[:message])
    content_attributes = { external_created_at: baileys_extract_message_timestamp(@raw_message[:messageTimestamp]) }
    content_attributes[:external_sender_name] = 'WhatsApp' unless incoming?

    if type == 'reaction'
      content_attributes[:in_reply_to_external_id] = msg.dig(:reactionMessage, :key, :id)
      content_attributes[:is_reaction] = true
    elsif reply_to_message_id
      content_attributes[:in_reply_to_external_id] = reply_to_message_id
    elsif type == 'unsupported'
      content_attributes[:is_unsupported] = true
    end

    referral = normalize_baileys_referral(message_context_info)
    content_attributes[:referral] = referral if referral.present?

    content_attributes
  end

  def attach_media_to_message
    attachment_file = download_attachment_file
    msg = unwrap_ephemeral_message(@raw_message[:message])

    attachment = @message.attachments.build(
      account_id: @message.account_id,
      file_type: file_content_type.to_s,
      file: { io: attachment_file, filename: build_attachment_filename, content_type: message_mimetype }
    )
    attachment.meta = { is_recorded_audio: true } if msg.dig(:audioMessage, :ptt)
  rescue Down::Error => e
    @message.is_unsupported = true
    Rails.logger.error "Failed to download attachment for message #{raw_message_id}: #{e.message}"
  end

  def download_attachment_file
    Down.download(
      inbox.channel.media_url(@raw_message.dig(:key, :id)),
      headers: inbox.channel.api_headers
    )
  end

  def build_attachment_filename
    msg = unwrap_ephemeral_message(@raw_message[:message])
    filename = msg.dig(:documentMessage, :fileName) || msg.dig(:documentWithCaptionMessage, :message, :documentMessage, :fileName)
    return filename if filename.present?

    ext = ".#{message_mimetype.split(';').first.split('/').last}" if message_mimetype.present?
    "#{file_content_type}_#{raw_message_id}_#{Time.current.strftime('%Y%m%d')}#{ext}"
  end

  def should_attach_media?
    %w[image file video audio sticker].include?(message_type)
  end
end
