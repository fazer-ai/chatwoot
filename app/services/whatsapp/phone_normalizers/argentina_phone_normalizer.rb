# Handles Argentina phone number normalization
#
# Argentina phone numbers can appear with or without "9" after country code
# This normalizer removes the "9" when present to create consistent format: 54 + area + number
class Whatsapp::PhoneNormalizers::ArgentinaPhoneNormalizer < Whatsapp::PhoneNormalizers::BasePhoneNormalizer
  def normalize(waid)
    return waid unless handles_country?(waid)

    # Remove "9" after country code if present (549 → 54)
    waid.sub(/^549/, '54')
  end

  # An Argentinian mobile number may appear with or without the "9" after the
  # country code, so both forms are variants of the same line.
  def variants(waid)
    return [waid] unless handles_country?(waid)

    [waid, waid.start_with?('549') ? waid.sub(/^549/, '54') : "549#{waid[2..]}"].uniq
  end

  private

  def country_code_pattern
    /^54/
  end
end
