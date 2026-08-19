# Whether an address points inside this deployment.
#
# What it answers decides two things: whether an inbox may be pointed at it at all, and
# whether outbound media is offered at the public URL or at INTERNAL_HOST_URL. Both are
# asked while saving or while building a URL, so nothing here resolves a name: that is a
# network call, and the calls themselves are filtered when they are made.
module Whatsapp::Session::PrivateAddress
  class << self
    def url?(value)
      uri = URI.parse(value.to_s)
      uri.is_a?(URI::HTTP) && host?(uri.host.to_s)
    rescue URI::InvalidURIError
      false
    end

    def http_url?(value)
      uri = URI.parse(value.to_s)
      uri.is_a?(URI::HTTP) && uri.host.present?
    rescue URI::InvalidURIError
      false
    end

    def host?(host)
      host = host.delete_prefix('[').delete_suffix(']').delete_suffix('.').downcase
      host.present? && (name?(host) || address?(host))
    end

    private

    # The trailing dot stripped above is the root label, so `localhost.` is still
    # localhost. A name with no dot at all cannot be public either, and is how a service
    # next door is addressed on a compose network.
    def name?(host)
      host == 'localhost' || host.end_with?('.localhost') || host.exclude?('.')
    end

    def address?(host)
      address = IPAddr.new(host)
      address.loopback? || address.private? || address.link_local? || address.to_s == '0.0.0.0'
    rescue IPAddr::Error
      false
    end
  end
end
