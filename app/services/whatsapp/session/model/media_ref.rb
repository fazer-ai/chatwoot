# How to fetch the bytes of a media message. Bytes never travel inside an event: the
# connector publishes a blob it serves over its internal HTTP port, Uazapi publishes
# either a direct URL or a message id that needs a /message/download round trip.
class Whatsapp::Session::Model::MediaRef < Data.define(:kind, :id, :url, :headers, :size, :mime, :sha256, :expires_at)
  include Whatsapp::Session::Model::Serializable

  KINDS = %w[url connector_blob uazapi_message].freeze

  def self.url(url, mime: nil, size: nil)
    new(kind: 'url', url: url, mime: mime, size: size)
  end

  def initialize(**attributes)
    kind = attributes[:kind].to_s
    raise Whatsapp::Session::Errors::InvalidPayload, "unknown media ref kind: #{kind}" unless KINDS.include?(kind)

    super(**attributes, kind: kind)
  end

  # A URL that has already lapsed is not something to try: the connector serves its blobs
  # for a bounded time and answers 404 afterwards, and the answer to that is to ask it for
  # the bytes again, not to tell the agent the media is gone.
  def fetchable?
    url.present? && !expired?
  end

  def expired?
    expires_at.present? && Time.zone.at(expires_at / 1000.0) <= Time.current
  end
end
