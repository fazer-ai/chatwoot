# The two markers `Avatar::AvatarFromUrlJob` keeps on a Contact to avoid refetching the
# same picture: the last sync time (a one minute rate limit) and a hash of the URL it
# already fetched. That job stamps both even on the run it skipped, so anything that
# knows the stored avatar is out of date has to clear them first or its refresh is
# dropped, and so is every later attempt at the same URL.
#
# Three callers know that: the contact picture-changed event, the forced group photo
# refresh, and the group rejoin snapshot.
module Whatsapp::Session::AvatarSync
  MARKERS = %w[last_avatar_sync_at avatar_url_hash].freeze

  module_function

  # Read and written under the row lock. `additional_attributes` is one JSON column that
  # also carries the group's description, its settings and `group_left`, and the caller
  # is often a job that fetched group info first: writing the whole hash it read before
  # that round trip would throw away whatever landed in the meantime.
  def reset(contact)
    return if contact.blank?

    contact.with_lock do
      attributes = (contact.additional_attributes || {}).except(*MARKERS)
      next if attributes == contact.additional_attributes

      contact.update_columns(additional_attributes: attributes) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  # Clears the markers and asks for the picture at `url`, which the caller already has.
  def refetch(contact, url)
    return if contact.blank? || url.blank?

    reset(contact)
    ::Avatar::AvatarFromUrlJob.perform_later(contact, url)
  end
end
