# The inbox cache key answers "has an inbox changed"; the browser reads it as "is my cached
# copy still correct". Those are the same question only while the payload depends on nothing
# but the record, and it does not: `capabilities` follows WHATSAPP_GROUPS_ENABLED and
# `forwarding_enabled` follows MAILER_INBOUND_EMAIL_DOMAIN. Flip either and every warm cache
# keeps serving rows built under the old setting, because no inbox was written and the key
# never moved. The same gap swallows a payload that grew a field on deploy.
#
# So the key carries a fingerprint of everything else the payload is derived from. Doing it
# here rather than in the dashboard is what makes it complete: the server is the only side
# that knows what it serialized, and one key covers every browser without the two versions
# having to be bumped in step.
module AccountInboxPayloadFingerprint
  extend ActiveSupport::Concern

  # Bump on any change to the shape of `api/v1/models/_inbox.json.jbuilder`.
  PAYLOAD_VERSION = 2

  def cache_keys
    keys = super
    keys[:inbox] = "#{keys[:inbox]}-#{inbox_payload_fingerprint}"
    keys
  end

  private

  # Deliberately not memoized: `with_modified_env` in a spec, and a console flipping a
  # setting, both have to be visible. It is a digest of a short string, computed once per
  # cache-key read.
  def inbox_payload_fingerprint
    inputs = [
      PAYLOAD_VERSION,
      Whatsapp::Session::Registry.groups_enabled?,
      ENV.fetch('MAILER_INBOUND_EMAIL_DOMAIN', '').present?
    ]

    Digest::MD5.hexdigest(inputs.join('|'))[0, 8]
  end
end
