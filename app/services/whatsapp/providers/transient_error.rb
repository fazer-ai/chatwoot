class Whatsapp::Providers::TransientError < StandardError
  # Meta error codes the WhatsApp Cloud API documents as "please try again"
  # transients — usually resolve within seconds. Kept small on purpose;
  # widening this list without evidence would trade slow failures for slow
  # retries when the underlying cause is actually permanent.
  # https://developers.facebook.com/docs/whatsapp/cloud-api/support/error-codes/
  CODES = %w[131000 131016 131052 131053 133000].freeze

  attr_reader :error_code, :meta_message

  def self.transient?(error_code)
    return false if error_code.nil?

    CODES.include?(error_code.to_s)
  end

  def initialize(error_code:, meta_message:)
    @error_code = error_code
    @meta_message = meta_message
    super("Meta WhatsApp transient error #{error_code}: #{meta_message}")
  end
end
