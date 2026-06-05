# For Brazilian numbers, the WhatsApp account may be registered under the
# pre-2012 12-digit format (no "9" after the area code) even when the line
# itself is the modern 13-digit form, and vice versa. Operators don't
# always know which one a given patient uses when they create the contact
# through the pencil flow.
#
# This service asks the Baileys provider which JID the WhatsApp servers
# actually associate with the number (via on_whatsapp). The canonical
# phone returned is the one that should be persisted on the contact and
# used as the contact_inbox source_id — eliminating the duplicate created
# later when the patient replies in the alternate format.
#
# Returns the input phone unchanged when:
#   - the channel isn't a Baileys WhatsApp channel
#   - the phone isn't a Brazilian one (other countries don't need this)
#   - on_whatsapp fails or both candidates report exists=false
class Whatsapp::CanonicalPhoneResolverService
  BRAZILIAN_PHONE_REGEX = /\A55\d{10,11}\z/
  BRAZILIAN_13D_REGEX = /\A55\d{2}9\d{8}\z/

  def initialize(channel:, phone:)
    @channel = channel
    @phone = phone.to_s.delete('+')
  end

  def resolve
    return @phone unless baileys_channel? && brazilian_phone?

    candidates = phone_candidates
    return @phone if candidates.size <= 1

    canonical = candidates.find { |candidate| phone_registered?(candidate) }
    canonical || @phone
  rescue StandardError => e
    Rails.logger.warn("[canonical-phone] resolve failed for #{@phone}: #{e.message}")
    @phone
  end

  private

  def baileys_channel?
    @channel.is_a?(Channel::Whatsapp) && @channel.provider == 'baileys'
  end

  def brazilian_phone?
    @phone.match?(BRAZILIAN_PHONE_REGEX)
  end

  # Always return both candidates in [normalized_13d, legacy_12d] order so the
  # 13d form is tried first — matches the format the great majority of modern
  # WhatsApp accounts are registered under.
  def phone_candidates
    normalized = Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer.new.normalize(@phone)
    alternative = strip_brazilian_9(normalized)
    [normalized, alternative].compact.uniq
  end

  def strip_brazilian_9(phone)
    return nil unless phone.match?(BRAZILIAN_13D_REGEX)

    "#{phone[0, 4]}#{phone[5..]}"
  end

  def phone_registered?(phone)
    response = @channel.on_whatsapp("#{phone}@s.whatsapp.net")
    response.is_a?(Hash) && response['exists'] == true
  end
end
