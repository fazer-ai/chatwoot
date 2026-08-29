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
# Kept on the channel, which already carries a JSON column for provider state, so this
# needs no table of its own. Keyed by folder and stamped with `UIDVALIDITY`: a provider
# that renumbers a folder invalidates its own cursor, and the run starts that folder over
# rather than skipping into the middle of it.
class Import::Email::Cursor
  KEY = 'import_cursor'.freeze

  def initialize(channel)
    @channel = channel
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

    pending[folder] = { 'uidvalidity' => uidvalidity, 'uid' => uid }
  end

  def flush
    return if pending.empty?

    config = @channel.provider_config.presence || {}
    config[KEY] = (config[KEY] || {}).merge(pending)
    @channel.update_column(:provider_config, config) # rubocop:disable Rails/SkipsModelValidations
    @pending = {}
  end

  def reset
    config = @channel.provider_config.presence || {}
    return if config[KEY].blank?

    @channel.update_column(:provider_config, config.except(KEY)) # rubocop:disable Rails/SkipsModelValidations
  end

  def to_s
    stored = (@channel.provider_config.presence || {})[KEY] || {}
    return 'do inicio' if stored.empty?

    stored.map { |folder, at| "#{folder}>#{at['uid']}" }.join(', ')
  end

  private

  def pending = @pending ||= {}

  def mark_for(folder, uidvalidity)
    stored = ((@channel.provider_config.presence || {})[KEY] || {})[folder]
    return 0 if stored.blank? || stored['uidvalidity'] != uidvalidity

    stored['uid'].to_i
  end
end
