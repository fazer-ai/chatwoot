# This Builder will create a contact inbox with specified attributes. If the contact inbox already exists, it will be returned.
# For Specific Channels like whatsapp, email etc . it smartly generated appropriate the source id when none is provided.

class ContactInboxBuilder
  pattr_initialize [:contact, :inbox, :source_id, { hmac_verified: false, validate_baileys_phone: false }]

  def perform
    normalize_phone_for_baileys! if validate_baileys_phone && baileys_whatsapp_inbox?
    @source_id ||= generate_source_id
    create_contact_inbox if source_id.present?
  end

  private

  def baileys_whatsapp_inbox?
    @inbox.channel_type == 'Channel::Whatsapp' && @inbox.channel.provider == 'baileys'
  end

  # WhatsApp matches the canonical phone for an account, but Baileys requires
  # the exact number registered there. For Brazilian mobile numbers the leading
  # "9" may or may not be present in the user-typed value; sending to the wrong
  # variant fails silently. Use on_whatsapp to resolve the canonical number and
  # align the contact (and source_id) with what Baileys expects. Provider
  # lookup errors are swallowed; write/merge errors must surface so the caller
  # sees inconsistent state.
  def normalize_phone_for_baileys!
    return if @contact.phone_number.blank?

    old_source_id_candidate = @contact.phone_number.delete('+')

    canonical_phone = fetch_canonical_baileys_phone
    return if canonical_phone.blank? || canonical_phone == @contact.phone_number

    apply_canonical_phone(canonical_phone)

    @source_id = canonical_phone.delete('+') if @source_id == old_source_id_candidate
  end

  def fetch_canonical_baileys_phone
    response = @inbox.channel.on_whatsapp(@contact.phone_number)
    return unless response.is_a?(Hash) && response['exists']

    jid_digits = response['jid'].to_s.split('@').first
    return if jid_digits.blank?

    "+#{jid_digits}"
  rescue StandardError => e
    Rails.logger.warn("[WHATSAPP][BAILEYS] phone normalization via on_whatsapp failed (ignored): #{e.class.name}: #{e.message}")
    nil
  end

  def apply_canonical_phone(canonical_phone)
    existing = @inbox.account.contacts.where.not(id: @contact.id).find_by(phone_number: canonical_phone)

    if existing
      @contact = ContactMergeAction.new(account: @inbox.account, base_contact: existing, mergee_contact: @contact).perform
    else
      @contact.update!(phone_number: canonical_phone)
    end
  end

  def generate_source_id
    case @inbox.channel_type
    when 'Channel::TwilioSms'
      twilio_source_id
    when 'Channel::Whatsapp'
      wa_source_id
    when 'Channel::Email'
      email_source_id
    when 'Channel::Sms'
      phone_source_id
    when 'Channel::Api', 'Channel::WebWidget'
      SecureRandom.uuid
    else
      raise "Unsupported operation for this channel: #{@inbox.channel_type}"
    end
  end

  def email_source_id
    raise ActionController::ParameterMissing, 'contact email' unless @contact.email

    @contact.email
  end

  def phone_source_id
    raise ActionController::ParameterMissing, 'contact phone number' unless @contact.phone_number

    @contact.phone_number
  end

  def wa_source_id
    raise ActionController::ParameterMissing, 'contact phone number' unless @contact.phone_number

    # whatsapp doesn't want the + in e164 format
    @contact.phone_number.delete('+').to_s
  end

  def twilio_source_id
    raise ActionController::ParameterMissing, 'contact phone number' unless @contact.phone_number

    case @inbox.channel.medium
    when 'sms'
      @contact.phone_number
    when 'whatsapp'
      "whatsapp:#{@contact.phone_number}"
    end
  end

  def create_contact_inbox
    attrs = {
      contact_id: @contact.id,
      inbox_id: @inbox.id,
      source_id: @source_id
    }

    ::ContactInbox.where(attrs).first_or_create!(hmac_verified: hmac_verified || false)
  rescue ActiveRecord::RecordNotUnique
    Rails.logger.info("[ContactInboxBuilder] RecordNotUnique #{@source_id} #{@contact.id} #{@inbox.id}")
    update_old_contact_inbox
    retry
  end

  def update_old_contact_inbox
    # The race condition occurs when there’s a contact inbox with the
    # same source ID but linked to a different contact. This can happen
    # if the agent updates the contact’s email or phone number, or
    # if the contact is merged with another.
    #
    # We update the old contact inbox source_id to a random value to
    # avoid disrupting the current flow. However, the root cause of
    # this issue is a flaw in the contact inbox model design.
    # Contact inbox is essentially tracking a session and is not
    # needed for non-live chat channels.
    raise ActiveRecord::RecordNotUnique unless allowed_channels?

    contact_inbox = ::ContactInbox.find_by(inbox_id: @inbox.id, source_id: @source_id)
    return if contact_inbox.blank?

    contact_inbox.update!(source_id: new_source_id)
  end

  def new_source_id
    if @inbox.whatsapp? || @inbox.sms? || @inbox.twilio?
      "whatsapp:#{@source_id}#{rand(100)}"
    else
      "#{rand(10)}#{@source_id}"
    end
  end

  def allowed_channels?
    @inbox.email? || @inbox.sms? || @inbox.twilio? || @inbox.whatsapp?
  end
end

ContactInboxBuilder.prepend_mod_with('ContactInboxBuilder')
