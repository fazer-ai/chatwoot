# What a credential check answers when it could not reach a verdict.
#
# `validate_provider_config?` has two honest answers, the credential works or the provider refused it,
# and a boolean can only say those two. The third outcome is that nothing came back that says either:
# the socket timed out, the connection was refused, the provider answered that it could not answer
# right now, or answered something this side cannot read. Returned as `false`, that becomes "Invalid
# Credentials" to an operator whose credentials may be perfect; left to escape, it becomes a 500 that
# says the application broke (fazer-ai/chatwoot#598). So it is raised as its own class, and the one
# caller, `Channel::Whatsapp#validate_provider_config`, turns it into a validation error of its own.
#
# The rescue here is wide on purpose and narrow in scope, the same arrangement as
# Whatsapp::TransportFailure: anything StandardError can be at the HTTP call is a transport failure by
# construction, and an enumerated list would be a promise to have thought of every way a socket can
# fail. What keeps it honest is that nothing but the call goes inside the block. A defect of our own
# around the call, a NoMethodError before or between the requests, is not a check that failed to
# conclude, and must not reach the operator as one: it stays out of the block and escapes as itself.
module Whatsapp::CredentialCheck
  class Unavailable < StandardError; end

  private

  def credential_check_request
    yield
  rescue StandardError => e
    # The class only. A message can carry the request URL, and Z-API puts the token in the path.
    raise Unavailable, e.class.name
  end

  # A 5xx is the provider, or whatever stands in front of it, saying it cannot answer right now. A 429
  # is a ceiling on how often this account may ask. Neither is a statement about the credential, and a
  # refusal is the one reading that would send the operator to replace a token that works.
  def ensure_credential_verdict!(response)
    return unless response.code == 429 || response.code >= 500

    raise Unavailable, "HTTP #{response.code}"
  end

  # For a body the verdict depends on. When the answer is already known, as with a refusal whose body
  # only feeds a log line, an unreadable body must not change it: read it with a rescue of your own.
  def credential_check_body(response)
    response.parsed_response
  rescue JSON::ParserError
    raise Unavailable, 'unreadable body'
  end
end
