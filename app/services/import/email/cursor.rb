# How far into a folder a run has already looked.
#
# The inbox is not enough to answer that. A resumable pass re-walks the folder and asks
# what the inbox already holds, which works for messages it wrote and says nothing about
# the ones it read and declined -- and on a support mailbox the declined ones are most of
# it, since the default takes customer mail and leaves the outgoing copies, the receipts
# and the ticketing system's own notifications behind.
#
# Left at that, the run never gets past them. Every pass re-downloads the same declined
# mail, pays the same bytes for it, and stops in the same place when the daily budget runs
# out, so a stretch of excluded traffic wider than one day's budget is a wall no number of
# passes crosses.
#
# Kept in a column of its own, and not in `provider_config`: the OAuth refresh services
# replace that hash wholesale on every token renewal, so a Google or Microsoft inbox would
# delete its own cursor long before a multi-day import finished -- and writing the cursor
# back over the same hash could clobber credentials that had just been refreshed.
#
# Keyed by folder and stamped with `UIDVALIDITY`: a provider that renumbers a folder
# invalidates its own cursor, and the run starts that folder over rather than skipping
# into the middle of it.
#
# Stamped with the selection for the same reason, because a mark only means anything
# against the question that produced it. UIDs rise with arrival, so older mail carries
# lower UIDs: a pass restricted to recent mail leaves a high mark, and a later pass widened
# to the whole mailbox would have every older UID filtered out by that mark and report the
# folder exhausted without classifying one of them -- the silent version of the failure,
# since nothing errors and the numbers look like a finished import. Change the search terms
# or the kinds and the folder starts over.
class Import::Email::Cursor
  def initialize(channel, selection: nil)
    @channel = channel
    @selection = Digest::SHA256.hexdigest(selection.to_json)[0, 16]
  end

  # UIDs above the mark, in the order the caller gave them.
  def unseen(folder, uidvalidity, uids)
    mark = mark_for(folder, uidvalidity)
    return uids if mark.zero?

    uids.select { |uid| uid > mark }
  end

  # Advances only forward, and only to a UID the caller is done with. Writing is left to
  # `flush`, so a run pays one update per batch rather than one per message.
  def advance(folder, uidvalidity, uid)
    current = pending[folder]
    return if current && current['uidvalidity'] == uidvalidity && current['uid'] >= uid

    pending[folder] = { 'uidvalidity' => uidvalidity, 'uid' => uid, 'selection' => @selection }
  end

  def flush
    return if pending.empty?

    @channel.update_column(:import_cursor, stored.merge(pending)) # rubocop:disable Rails/SkipsModelValidations
    @pending = {}
  end

  def reset
    @pending = {}
    return if stored.blank?

    @channel.update_column(:import_cursor, {}) # rubocop:disable Rails/SkipsModelValidations
  end

  def to_s
    return 'do inicio' if stored.blank?

    stored.map { |folder, at| "#{folder}>#{at['uid']}" }.join(', ')
  end

  private

  def stored = @channel.import_cursor.presence || {}
  def pending = @pending ||= {}

  def mark_for(folder, uidvalidity)
    at = stored[folder]
    return 0 if at.blank? || at['uidvalidity'] != uidvalidity || at['selection'] != @selection

    at['uid'].to_i
  end
end
