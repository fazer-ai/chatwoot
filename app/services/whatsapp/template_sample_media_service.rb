# The sample media a template ships with (`components[].example.header_handle[0]`) is hosted on Meta's
# own CDN, which answers 403 to Meta's media fetcher. Passing it as a `link` therefore fails every send
# with "131053 Media upload error", even though the very same URL downloads fine from anywhere else.
# Uploading the file to the media store once and addressing it by id sidesteps the fetch entirely.
class Whatsapp::TemplateSampleMediaService
  # Meta keeps uploaded media for 30 days; expire a little early so an id is never used past its life.
  CACHE_TTL = 25.days

  pattr_initialize [:channel!, :url!]

  def media_id
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL) { upload }
  end

  private

  def cache_key
    "whatsapp_template_sample_media/#{channel.id}/#{Digest::SHA256.hexdigest(url)}"
  end

  def upload
    file = Down.download(url)
    channel.provider_service.upload_media(file, file.content_type)
  rescue Down::ClientError, Down::InvalidUrl => e
    # Only a 4xx or a malformed URL is the media's own fault and worth failing the message over. A
    # timeout, a refused connection or a 5xx is the CDN having a bad minute: those propagate so Sidekiq
    # retries, instead of dropping the send for good over a blip.
    raise CustomExceptions::Whatsapp::MediaUploadError, "Could not download the template sample media: #{e.message}"
  ensure
    file&.close
    file&.unlink
  end
end
