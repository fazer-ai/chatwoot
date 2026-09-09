# Marcel gem may detect OGG Opus files as audio/opus instead of audio/ogg.
# This is problematic because WhatsApp Cloud API (and other services)
# expect audio/ogg for OGG container files with the Opus codec.
#
# This initializer patches ActiveStorage::Blob to normalize audio/opus → audio/ogg
# at identification time, preventing the wrong content_type from being persisted.
#
# It covers .opus as well as .ogg, because audio/opus is never a statement about the bytes:
# Marcel reads one and the same file as audio/ogg by content and as audio/opus only once it
# is shown the name. .opus is an Ogg container (RFC 7845) and audio/ogg is the type
# registered for it, so this is the correct type and not only the one WhatsApp takes.
ActiveSupport.on_load(:active_storage_blob) do
  prepend(Module.new do
    private

    def identify_content_type(io = nil)
      detected = super
      detected == 'audio/opus' && filename.to_s.downcase.end_with?(*Attachment::OPUS_EXTENSIONS) ? 'audio/ogg' : detected
    end
  end)
end
