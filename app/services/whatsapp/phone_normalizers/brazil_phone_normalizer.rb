# Handles Brazil phone number normalization
# ref: https://github.com/chatwoot/chatwoot/issues/5840
#
# Brazil changed its mobile number system by adding a "9" prefix to existing numbers.
# This normalizer adds the "9" digit if the number is 12 digits (making it 13 digits total)
# to match the new format: 55 + DDD + 9 + number
class Whatsapp::PhoneNormalizers::BrazilPhoneNormalizer < Whatsapp::PhoneNormalizers::BasePhoneNormalizer
  COUNTRY_CODE_LENGTH = 2
  DDD_LENGTH = 2

  def normalize(waid)
    return waid unless handles_country?(waid)

    ddd = waid[COUNTRY_CODE_LENGTH, DDD_LENGTH]
    number = waid[COUNTRY_CODE_LENGTH + DDD_LENGTH, waid.length - (COUNTRY_CODE_LENGTH + DDD_LENGTH)]
    normalized_number = "55#{ddd}#{number}"
    normalized_number = "55#{ddd}9#{number}" if normalized_number.length != 13
    normalized_number
  end

  # A Brazilian mobile number may be registered on WhatsApp with or without the
  # ninth digit, so both forms are variants of the same line.
  def variants(waid)
    return [waid] unless handles_country?(waid)

    ddd = waid[COUNTRY_CODE_LENGTH, DDD_LENGTH]
    number = waid[(COUNTRY_CODE_LENGTH + DDD_LENGTH)..]

    candidates = [waid]
    candidates << "55#{ddd}9#{number}" if number.length == 8
    candidates << "55#{ddd}#{number[1..]}" if number.length == 9 && number.start_with?('9')
    candidates
  end

  private

  def country_code_pattern
    /^55/
  end
end
