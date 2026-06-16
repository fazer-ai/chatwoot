module Whatsapp::IncomingMessageServiceHelpers # rubocop:disable Metrics/ModuleLength
  def download_attachment_file(attachment_payload)
    Down.download(inbox.channel.media_url(attachment_payload[:id]), headers: inbox.channel.api_headers)
  end

  def conversation_params
    params = {
      account_id: @inbox.account_id,
      inbox_id: @inbox.id,
      contact_id: @contact.id,
      contact_inbox_id: @contact_inbox.id
    }
    # First-touch attribution persisted only when the conversation is created from
    # the originating message: the rich ad/post referral (externalAdReply) and/or
    # the WhatsApp entry point (e.g. click_to_chat_link from a profile/bio link).
    attribution = { referral: @referral, entry_point: @entry_point }.compact
    params[:additional_attributes] = attribution if attribution.present?
    params
  end

  def processed_params
    @processed_params ||= params
  end

  def account
    @account ||= inbox.account
  end

  def message_type
    messages_data.first[:type]
  end

  def message_content(message)
    # TODO: map interactive messages back to button messages in chatwoot
    message.dig(:text, :body) ||
      message.dig(:button, :text) ||
      message.dig(:interactive, :button_reply, :title) ||
      message.dig(:interactive, :list_reply, :title) ||
      message.dig(:name, :formatted_name) ||
      message.dig(:reaction, :emoji) ||
      referral_fallback_content(message)
  end

  # Edited messages nest the new content under `edit.message`, which carries its own
  # type. Reuse message_content for text/interactive bodies and fall back to the
  # media caption for image/video/document edits.
  def edited_message_content(edited)
    return if edited.blank?

    message_content(edited) ||
      edited.dig(:image, :caption) ||
      edited.dig(:video, :caption) ||
      edited.dig(:document, :caption)
  end

  # Ad-click webhooks can arrive with no textual body (e.g. request_welcome), so
  # fall back to the ad headline/body to keep the message renderable.
  def referral_fallback_content(message)
    ref = message[:referral]
    return if ref.blank?

    ref[:headline].presence || ref[:body].presence
  end

  # Normalizes the WhatsApp Cloud API `referral` object (sent on the first
  # message after a Click-to-WhatsApp ad click) to a provider-agnostic hash.
  def normalize_cloud_referral(message)
    ref = message[:referral]
    return if ref.blank?

    {
      source_type: ref[:source_type],
      source_id: ref[:source_id],
      source_url: ref[:source_url],
      ctwa_clid: ref[:ctwa_clid],
      title: ref[:headline],
      body: ref[:body],
      media_type: ref[:media_type]&.to_s&.downcase,
      thumbnail_url: ref[:image_url] || ref[:thumbnail_url] || ref[:video_url]
    }.compact.presence
  end

  # Normalizes the Baileys `contextInfo.externalAdReply` to the same shape as
  # `normalize_cloud_referral` so the frontend reads a single referral payload.
  def normalize_baileys_referral(context_info)
    ad = context_info&.dig(:externalAdReply)
    return if ad.blank?

    {
      source_type: ad[:sourceType],
      source_id: ad[:sourceId],
      source_url: ad[:sourceUrl],
      ctwa_clid: ad[:ctwaClid],
      title: ad[:title],
      body: ad[:body],
      media_type: baileys_media_type(ad[:mediaType]),
      thumbnail_url: ad[:thumbnailUrl]
    }.compact.presence
  end

  # Baileys serializes the externalAdReply MediaType proto enum as a number
  # (0=none, 1=image, 2=video), but some layers emit the string name instead.
  # Handle both so the frontend always gets a lowercase string.
  def baileys_media_type(value)
    return if value.nil?
    return { 0 => 'none', 1 => 'image', 2 => 'video' }[value] if value.is_a?(Integer)

    value.to_s.downcase.presence
  end

  # Lightweight WhatsApp entry-point attribution from Baileys `contextInfo`.
  # Present on first-contact messages even without an ad (e.g. a profile/bio
  # click-to-chat link reports `click_to_chat_link`). Does NOT render the ad card.
  def normalize_baileys_entry_point(context_info)
    source = context_info&.dig(:entryPointConversionSource)
    return if source.blank?

    { source: source, app: context_info[:entryPointConversionApp].presence }.compact.presence
  end

  def file_content_type(file_type)
    return :image if %w[image sticker].include?(file_type)
    return :audio if %w[audio voice].include?(file_type)
    return :video if ['video'].include?(file_type)
    return :location if ['location'].include?(file_type)
    return :contact if ['contacts'].include?(file_type)

    :file
  end

  def unprocessable_message_type?(message_type)
    %w[ephemeral request_welcome].include?(message_type)
  end

  def reaction_removal?
    message_type == 'reaction' && messages_data.first.dig(:reaction, :emoji).blank?
  end

  def processed_waid(waid)
    Whatsapp::PhoneNumberNormalizationService.new(inbox).normalize_and_find_contact_by_provider(waid, :cloud)
  end

  def whatsapp_phone_number(identifier)
    identifier = identifier.to_s
    return if identifier.blank?
    return unless identifier.match?(/\A\d{1,15}\z/)

    identifier
  end

  def error_webhook_event?(message)
    message.key?('errors')
  end

  def log_error(message)
    Rails.logger.warn "Whatsapp Error: #{message['errors'][0]['title']} - contact: #{message['from']}"
  end

  def process_in_reply_to(message)
    @in_reply_to_external_id = message['context']&.[]('id')
    @in_reply_to_external_id = message.dig(:reaction, :message_id) if message[:type] == 'reaction'
  end

  def find_message_by_source_id(source_id)
    return unless source_id

    @message = inbox.messages.find_by(source_id: source_id)
  end

  def message_under_process?
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: "#{inbox.id}_#{messages_data.first[:id]}")
    Redis::Alfred.get(key)
  end

  def acquire_message_processing_lock
    return false if messages_data.blank?

    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: "#{inbox.id}_#{messages_data.first[:id]}")
    Redis::Alfred.set(key, true, nx: true, ex: 1.day)
  end

  def clear_message_source_id_from_redis
    key = format(Redis::RedisKeys::MESSAGE_SOURCE_KEY, id: "#{inbox.id}_#{messages_data.first[:id]}")
    ::Redis::Alfred.delete(key)
  end

  # Lock by contact phone to prevent race conditions when multiple messages
  # from the same contact arrive simultaneously (e.g., WhatsApp albums).
  # Without this, each message could create its own conversation.
  def with_contact_lock(phone, timeout: 5.seconds)
    raise ArgumentError, 'A block is required for with_contact_lock' unless block_given?
    return yield if phone.blank?

    key = "WHATSAPP::CONTACT_LOCK::#{inbox.id}_#{phone}"
    start_time = Time.now.to_i
    lock_acquired = false

    while (Time.now.to_i - start_time) < timeout
      if Redis::Alfred.set(key, 1, nx: true, ex: timeout)
        lock_acquired = true
        break
      end

      sleep(0.1)
    end

    raise Timeout::Error, "Timeout acquiring contact lock for #{phone}" unless lock_acquired

    yield
  ensure
    Redis::Alfred.delete(key) if lock_acquired
  end
end
