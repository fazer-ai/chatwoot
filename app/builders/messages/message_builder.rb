class Messages::MessageBuilder # rubocop:disable Metrics/ClassLength
  include ::FileTypeHelper
  include ::EmailHelper
  include ::DataHelper

  attr_reader :message

  def initialize(user, conversation, params) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    @params = params
    @private = params[:private] || false
    @conversation = conversation
    @user = user
    @account = conversation.account
    @message_type = params[:message_type] || 'outgoing'
    @attachments = params[:attachments]
    @is_recorded_audio = params[:is_recorded_audio]
    @is_voice_message = ActiveModel::Type::Boolean.new.cast(params[:is_voice_message])
    @transcode_audio = params[:transcode_audio]
    @attachments_metadata = normalize_attachments_metadata(params[:attachments_metadata])
    @automation_rule = content_attributes&.dig(:automation_rule_id)
    return unless params.instance_of?(ActionController::Parameters)

    @in_reply_to = content_attributes&.dig(:in_reply_to)
    @is_reaction = content_attributes&.dig(:is_reaction)
    @items = content_attributes&.dig(:items)
    @zapi_args = content_attributes&.dig(:zapi_args)
  end

  def perform
    @message = @conversation.messages.build(message_params)
    process_attachments
    process_emails
    # When the message has no quoted content, it will just be rendered as a regular message
    # The frontend is equipped to handle this case
    process_email_content
    @message.save!
    @message
  end

  private

  # Extracts content attributes from the given params.
  # - Converts ActionController::Parameters to a regular hash if needed.
  # - Attempts to parse a JSON string if content is a string.
  # - Returns an empty hash if content is not present, if there's a parsing error, or if it's an unexpected type.
  def content_attributes
    params = convert_to_hash(@params)
    content_attributes = params.fetch(:content_attributes, {})

    return safe_parse_json(content_attributes) if content_attributes.is_a?(String)
    return content_attributes if content_attributes.is_a?(Hash)

    {}
  end

  def process_attachments
    return if @attachments.blank?

    @attachments.each do |uploaded_attachment|
      attachment = @message.attachments.build(
        account_id: @message.account_id,
        file: uploaded_attachment,
        # Someone on our side picked this file, so an empty one is a mistake we can still name to
        # their face instead of a message that turns red minutes later. An API inbox pushes
        # customer messages through this same builder, and those are ingestion: refusing one would
        # throw away its text along with the odd attachment.
        refuse_empty_file: !@message.incoming?
      )
      metadata = process_metadata(uploaded_attachment)
      attachment.meta = metadata if metadata.present?
      attachment.file_type = attachment_file_type(uploaded_attachment)
      tag_voice_message(attachment)
      transcode_attachment(attachment, file_like_source(uploaded_attachment)) if should_transcode?(attachment)
    end
  end

  def attachment_file_type(uploaded_attachment)
    return file_type(uploaded_attachment&.content_type) unless uploaded_attachment.is_a?(String)

    file_type(blob_for(uploaded_attachment)&.content_type)
  end

  # A direct upload sends an ActiveStorage signed ID, which is a String, so everything that used
  # to ask the uploaded file about itself has to ask the blob instead. Memoised because the file
  # type asks first and the metadata asks second, and resolving the same signed ID twice per
  # attachment is a query nobody needs.
  def blob_for(signed_id)
    @blobs_by_signed_id ||= {}
    return @blobs_by_signed_id[signed_id] if @blobs_by_signed_id.key?(signed_id)

    @blobs_by_signed_id[signed_id] = ActiveStorage::Blob.find_signed(signed_id)
  end

  # The name the caller used when they picked the file, whichever of the three shapes they sent.
  # An upload answers `original_filename`, a signed ID has to be resolved, and a blob, which is
  # what a macro and an automation rule pass, answers `filename`. Nil when there is no name to be
  # had, which is what both readers below already treat as "no metadata for this one" rather than
  # as an error.
  #
  # No caller sends a blob together with per-attachment metadata today, so that branch is
  # consistency rather than a fix. What it does remove is a latent raise: `recorded_audio_metadata`
  # asked a blob for `original_filename` too, and would have died the same way it died on a
  # signed ID the day someone passed both.
  def uploaded_filename(uploaded_attachment)
    return uploaded_attachment.original_filename if uploaded_attachment.respond_to?(:original_filename)
    return uploaded_attachment.filename.to_s if uploaded_attachment.respond_to?(:filename)
    return unless uploaded_attachment.is_a?(String)

    # The safe navigation cannot fire today and is kept on purpose: a signed ID that does not
    # resolve already raises one line earlier, at `attachments.build`, so nothing unresolvable
    # reaches this method. Dropping it would make that ordering load-bearing, and the failure it
    # would produce is a `NoMethodError` on nil in place of a legible 422.
    blob_for(uploaded_attachment)&.filename&.to_s
  end

  def tag_voice_message(attachment)
    return unless @is_voice_message && attachment.file_type == 'audio'

    attachment.meta = (attachment.meta || {}).merge('is_voice_message' => true)
  end

  def process_metadata(attachment)
    meta = {}
    meta.merge!(recorded_audio_metadata(attachment) || {})
    meta.merge!(custom_attachment_metadata(attachment) || {})
    meta.presence
  end

  def recorded_audio_metadata(attachment) # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    # NOTE: `is_recorded_audio` can be either a boolean, the string "true", or an array of file names.
    return unless @is_recorded_audio
    return { is_recorded_audio: true } if @is_recorded_audio == true || @is_recorded_audio == 'true'

    filename = uploaded_filename(attachment)
    return { is_recorded_audio: true } if @is_recorded_audio.is_a?(Array) && filename.in?(@is_recorded_audio)

    # FIXME: Remove backwards compatibility with old format.
    if @is_recorded_audio.is_a?(String)
      parsed = JSON.parse(@is_recorded_audio)
      { is_recorded_audio: true } if parsed.is_a?(Array) && filename.in?(parsed)
    end
  rescue JSON::ParserError
    nil
  end

  # A multipart request carries every value as a string, so `is_voice_message=false` arrives as
  # the string "false", which is `present?` and reads at both providers as an explicit yes. The
  # sibling top-level parameter is cast in the constructor; these were not, and the wrong value
  # was reaching the database rather than being misread on the way out. Only these two keys are
  # touched: everything else a caller puts in the metadata is theirs to shape.
  BOOLEAN_ATTACHMENT_METADATA_KEYS = %w[is_voice_message is_recorded_audio].freeze

  def cast_metadata_flags(values)
    return values unless values.is_a?(Hash)

    flags = values.slice(*BOOLEAN_ATTACHMENT_METADATA_KEYS)
                  .transform_values { |value| ActiveModel::Type::Boolean.new.cast(value) }
    values.merge(flags)
  end

  # Anything that is not a hash of its own is ignored rather than coerced. `to_h` answers a
  # different exception for each shape a caller can leave here -- NoMethodError for a String or
  # a number, TypeError for a bare array, ArgumentError for an array of short pairs -- and every
  # one of them took the whole request down. The single shape it does accept is worse than the
  # crashes: an array of pairs became metadata whose `is_voice_message` was the string "false",
  # which `cast_metadata_flags` never sees, because it only casts inside a Hash, and which both
  # providers read as an explicit yes.
  #
  # Ignoring keeps the message and the attachment, which is what the caller was asking for, and
  # leaves the reason in the log rather than in the answer.
  def custom_attachment_metadata(attachment)
    return unless @attachments_metadata.is_a?(Hash)

    filename = uploaded_filename(attachment)
    return unless filename

    metadata = @attachments_metadata[filename]
    return if metadata.blank?
    return metadata.to_h if metadata.is_a?(Hash)

    log_ignored_metadata("for #{filename}", metadata)
  end

  # Answers nil, which is what the caller does with an entry it cannot read.
  def log_ignored_metadata(where, value)
    Rails.logger.warn("[MESSAGE BUILDER] ignoring attachments_metadata #{where}: expected a hash, got #{value.class}")
    nil
  end

  # The same value can arrive one level up, and there it died even earlier: `attachments_metadata=x`
  # and `attachments_metadata[]=x` broke on `deep_stringify_keys` before any attachment was looked
  # at, so a guard on the per-file value alone would have left this one standing.
  def normalize_attachments_metadata(metadata)
    return if metadata.blank?

    metadata = metadata.to_unsafe_h if metadata.respond_to?(:to_unsafe_h)
    return log_ignored_metadata('at the top level', metadata) unless metadata.is_a?(Hash)

    metadata.deep_stringify_keys.transform_values { |values| cast_metadata_flags(values) }
  end

  def should_transcode?(attachment)
    @transcode_audio.present? && attachment.file_type == 'audio'
  end

  # Returns the uploaded file only when it's a real file-like object (ActionDispatch::Http::UploadedFile,
  # Tempfile, etc.). Direct-upload signed-ID Strings are not usable as source files for transcoding;
  # TranscodeService falls back to downloading from the blob in that case.
  def file_like_source(uploaded_attachment)
    return uploaded_attachment if uploaded_attachment.respond_to?(:path) || uploaded_attachment.respond_to?(:tempfile)
  end

  def transcode_attachment(attachment, uploaded_file = nil)
    Audio::TranscodeService.new(attachment, @transcode_audio, source_file: uploaded_file).perform
    attachment.meta ||= {}
    attachment.meta['is_recorded_audio'] = true
  rescue CustomExceptions::Audio::UnsupportedFormatError, CustomExceptions::Audio::TranscodingError => e
    Rails.logger.error("Audio transcoding failed, keeping original attachment: #{e.message}")
    attachment.meta ||= {}
    attachment.meta['audio_transcoding_failed'] = true
  end

  def process_emails
    return unless @conversation.inbox&.inbox_type == 'Email'

    cc_emails = process_email_string(@params[:cc_emails])
    bcc_emails = process_email_string(@params[:bcc_emails])
    to_emails = process_email_string(@params[:to_emails])

    all_email_addresses = cc_emails + bcc_emails + to_emails
    validate_email_addresses(all_email_addresses)

    @message.content_attributes[:cc_emails] = cc_emails
    @message.content_attributes[:bcc_emails] = bcc_emails
    @message.content_attributes[:to_emails] = to_emails
  end

  def process_email_content
    return unless should_process_email_content?

    @message.content_attributes ||= {}
    email_attributes = build_email_attributes
    @message.content_attributes[:email] = email_attributes
  end

  def process_email_string(email_string)
    return [] if email_string.blank?

    email_string.gsub(/\s+/, '').split(',')
  end

  def message_type
    if @conversation.inbox.channel_type != 'Channel::Api' && @message_type == 'incoming'
      raise StandardError, 'Incoming messages are only allowed in Api inboxes'
    end

    @message_type
  end

  def sender
    message_type == 'outgoing' ? (message_sender || @user) : @conversation.contact
  end

  def external_created_at
    @params[:external_created_at].present? ? { external_created_at: @params[:external_created_at] } : {}
  end

  def automation_rule_id
    @automation_rule.present? ? { content_attributes: { automation_rule_id: @automation_rule } } : {}
  end

  def campaign_id
    @params[:campaign_id].present? ? { additional_attributes: { campaign_id: @params[:campaign_id] } } : {}
  end

  def template_params
    @params[:template_params].present? ? { additional_attributes: { template_params: JSON.parse(@params[:template_params].to_json) } } : {}
  end

  def scheduled_message_metadata
    return {} if @params[:scheduled_message].blank?

    sm = @params[:scheduled_message]
    scheduled_by = { 'id' => sm.author_id, 'type' => sm.author_type }
    scheduled_by['name'] = sm.author.name if sm.author.respond_to?(:name)

    {
      additional_attributes: {
        scheduled_message_id: sm.id,
        scheduled_by: scheduled_by,
        scheduled_at: sm.updated_at.to_i
      }
    }
  end

  def message_sender
    return if @params[:sender_type] != 'AgentBot'

    AgentBot.where(account_id: [nil, @conversation.account.id]).find_by(id: @params[:sender_id])
  end

  def zapi_args
    @zapi_args.present? ? { zapi_args: @zapi_args } : {}
  end

  def message_params
    {
      account_id: @conversation.account_id,
      inbox_id: @conversation.inbox_id,
      message_type: message_type,
      content: @params[:content],
      private: @private,
      sender: sender,
      content_type: @params[:content_type],
      content_attributes: content_attributes.presence,
      items: @items,
      in_reply_to: @in_reply_to,
      is_reaction: @is_reaction,
      echo_id: @params[:echo_id],
      source_id: @params[:source_id]
    }.merge(external_created_at).merge(automation_rule_id).merge(campaign_id)
      .deep_merge(template_params).merge(zapi_args).deep_merge(scheduled_message_metadata)
  end

  def email_inbox?
    @conversation.inbox&.inbox_type == 'Email'
  end

  def should_process_email_content?
    email_inbox? && !@private && @message.content.present?
  end

  def build_email_attributes
    email_attributes = ensure_indifferent_access(@message.content_attributes[:email] || {})
    normalized_content = normalize_email_body(@message.content)

    # Process liquid templates in normalized content with code block protection
    processed_content = process_liquid_in_email_body(normalized_content)

    # Use custom HTML content if provided, otherwise generate from message content
    email_attributes[:html_content] = if custom_email_content_provided?
                                        build_custom_html_content
                                      else
                                        build_html_content(processed_content)
                                      end

    email_attributes[:text_content] = build_text_content(processed_content)
    email_attributes
  end

  def build_html_content(normalized_content)
    html_content = ensure_indifferent_access(@message.content_attributes.dig(:email, :html_content) || {})
    rendered_html = render_email_html(normalized_content)
    html_content[:full] = rendered_html
    html_content[:reply] = rendered_html
    html_content
  end

  def build_text_content(normalized_content)
    text_content = ensure_indifferent_access(@message.content_attributes.dig(:email, :text_content) || {})
    text_content[:full] = normalized_content
    text_content[:reply] = normalized_content
    text_content
  end

  def custom_email_content_provided?
    @params[:email_html_content].present?
  end

  def build_custom_html_content
    html_content = ensure_indifferent_access(@message.content_attributes.dig(:email, :html_content) || {})

    html_content[:full] = @params[:email_html_content]
    html_content[:reply] = @params[:email_html_content]

    html_content
  end

  # Liquid processing methods for email content
  def process_liquid_in_email_body(content)
    return content if content.blank?
    return content unless should_process_liquid?

    # Protect code blocks from liquid processing
    modified_content = modified_liquid_content(content)
    template = Liquid::Template.parse(modified_content)
    template.render(drops_with_sender)
  rescue Liquid::Error
    content
  end

  def should_process_liquid?
    @message_type == 'outgoing' || @message_type == 'template'
  end

  def drops_with_sender
    message_drops(@conversation).merge({
                                         'agent' => UserDrop.new(sender)
                                       })
  end
end

Messages::MessageBuilder.prepend_mod_with('Messages::MessageBuilder')
