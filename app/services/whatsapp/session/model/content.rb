# The body of a message, provider-neutral. Inbound content is built by the connector or by
# the Uazapi translator; outbound content is built by the message sender. Reaction is
# outbound-only: inbound reactions arrive as their own event, so handlers never have to
# branch on "is this message actually a reaction".
module Whatsapp::Session::Model::Content
  Serializable = Whatsapp::Session::Model::Serializable
  MediaRef = Whatsapp::Session::Model::MediaRef

  class Text < Data.define(:body)
    include Serializable
    wire_type 'text', embed: true
  end

  class Media < Data.define(:kind, :mime, :filename, :caption, :voice_note, :size, :duration, :thumbnail, :ref)
    include Serializable
    wire_type 'media', embed: true
    coerce ref: MediaRef
    defaults voice_note: false

    KINDS = %w[image video audio document sticker].freeze

    def initialize(**attributes)
      kind = attributes[:kind].to_s
      raise Whatsapp::Session::Errors::InvalidPayload, "unknown media kind: #{kind}" unless KINDS.include?(kind)

      super
    end

    # Maps to the `file_type` enum Chatwoot attachments use.
    def attachment_file_type
      case kind
      when 'image', 'sticker' then :image
      when 'video' then :video
      when 'audio' then :audio
      else :file
      end
    end
  end

  class Location < Data.define(:latitude, :longitude, :name, :address, :live)
    include Serializable
    wire_type 'location', embed: true
    defaults live: false
  end

  class Contacts < Data.define(:contacts)
    include Serializable
    wire_type 'contacts', embed: true
    defaults contacts: []
  end

  class Reaction < Data.define(:target_id, :emoji)
    include Serializable
    wire_type 'reaction', embed: true

    def removal?
      emoji.blank?
    end
  end

  class Rich < Data.define(:kind, :text, :media)
    include Serializable
    wire_type 'rich', embed: true
    coerce media: Media
  end

  class Unsupported < Data.define(:reason)
    include Serializable
    wire_type 'unsupported', embed: true

    REASONS = %w[unknown_type undecryptable protocol empty].freeze
  end

  CLASSES = [Text, Media, Location, Contacts, Reaction, Rich, Unsupported].freeze
  BY_TYPE = CLASSES.index_by(&:wire_type).freeze

  def self.from_h(hash)
    return if hash.nil?

    type = hash['type'] || hash[:type]
    klass = BY_TYPE[type]
    raise Whatsapp::Session::Errors::InvalidPayload, "unknown content type: #{type.inspect}" if klass.nil?

    klass.from_h(hash)
  end
end
