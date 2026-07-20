# This Builder will create a contact inbox with specified attributes. If the contact inbox already exists, it will be returned.
# For Specific Channels like whatsapp, email etc . it smartly generated appropriate the source id when none is provided.

class ContactInboxBuilder
  pattr_initialize [:contact, :inbox, :source_id, { hmac_verified: false }]

  def perform
    # Baileys always needs the canonical BR phone form for outbound routing,
    # regardless of whether the caller pre-computed a source_id. When the
    # pencil flow (ContactsController#create) passes an explicit
    # `source_id: <digits>`, the previous `||=` skipped `generate_source_id`
    # — which is where `wa_source_id` runs `resolve_canonical_phone_for_baileys`
    # — so the contact stayed on the 13d input and outbound messages to
    # pre-2012 accounts silently stopped at "sent".
    force_baileys_canonical_source_id if baileys_wa_channel?
    @source_id ||= generate_source_id
    create_contact_inbox if source_id.present?
  end

  private

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
    when 'Channel::Api', 'Channel::WebWidget', 'Channel::Simulator'
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

    # For Baileys channels, ask the provider whether the number is
    # registered under the 13d form or the legacy 12d Brazilian form,
    # and persist whichever the WhatsApp servers actually use. This
    # prevents the duplicate-contact problem when the operator types
    # the format the patient's account is NOT registered with.
    resolve_canonical_phone_for_baileys

    # whatsapp doesn't want the + in e164 format
    @contact.phone_number.delete('+').to_s
  end

  def resolve_canonical_phone_for_baileys
    return unless baileys_wa_channel?

    canonical = Whatsapp::CanonicalPhoneResolverService.new(
      channel: @inbox.channel,
      phone: @contact.phone_number
    ).resolve

    return if canonical.blank? || canonical == @contact.phone_number.delete('+')

    @contact.update!(phone_number: "+#{canonical}")
  end

  def baileys_wa_channel?
    @inbox.channel_type == 'Channel::Whatsapp' &&
      @inbox.channel.provider == 'baileys' &&
      @contact.phone_number.present?
  end

  # Runs the resolver + rewrites `@source_id` from the canonical phone,
  # even if the caller pre-computed one. Called only for Baileys WA where
  # source_id == phone digits by convention.
  def force_baileys_canonical_source_id
    resolve_canonical_phone_for_baileys
    @source_id = @contact.phone_number.delete('+').to_s
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
