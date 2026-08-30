# Walks a mailbox over IMAP and files what it finds.
#
# The loop, kept apart from the rake task so the pacing and the resume logic can be read
# and tested on their own. What makes it a backfill rather than a fetch is that it is
# built to be stopped: the byte budget ends a pass on purpose, a redeploy ends one by
# accident, and both leave the same state behind. Every pass re-walks the folders and asks
# the inbox what it already holds, keyed on Message-ID, so the only cost of stopping is
# the header scan on the way back in.
#
# Message-ID rather than a stored cursor because a mailbox is not a log: mail arrives
# out of order, folders are re-labelled, and a UID is only meaningful next to a
# UIDVALIDITY that the provider may bump. What the inbox holds is the one fact that
# survives all of that.
class Import::Email::Backfill
  # Gmail localises its special folders, so they are found by IMAP attribute rather than
  # by name. \All is the union of everything except Spam and Trash, which makes it the one
  # folder worth walking; Spam is added because a support mailbox misfiles real mail there.
  SPECIAL_ATTRS = %i[All Junk].freeze
  HEADER_BATCH = 200

  UNIMPORTABLE = Import::Email::Classifier::UNIMPORTABLE

  attr_reader :stats, :pacer, :stopped_by, :cursor

  # rubocop:disable Metrics/ParameterLists -- every one of these is an independent knob on
  # a run that is meant to be started, stopped and restarted with different settings; an
  # options object would only move the list one file over.
  def initialize(inbox:, kinds:, pacer:, folders: nil, terms: ['ALL'], attachments: nil, limit: nil)
    @inbox = inbox
    @channel = inbox.channel
    @kinds = Import::Email::Classifier.importable!(kinds)
    @pacer = pacer
    @folders = folders
    @terms = terms
    @limit = limit
    @attachments = Import::Email::AttachmentPolicy.build(attachments)
    @importer = Import::Email::HistoryImporter.new(attachments: @attachments)
    @cursor = Import::Email::Cursor.new(@channel, selection: selection)
    @stats = Hash.new(0)
    # After `@stats`, which it shares rather than copies: a run's tallies are one hash and
    # the collaborators write into it.
    @download = Import::Email::Download.new(pacer: @pacer, attachments: @attachments, stats: @stats)
    @stopped_by = nil
  end
  # rubocop:enable Metrics/ParameterLists

  # `progress` is called with (event, payload) as the run goes: :folder, :paused,
  # :imported, :error. Held on the instance rather than threaded through every frame,
  # because the loop is three levels deep and passing a block down all of them says
  # nothing about what the loop does.
  # `Array(...)` around the search rather than trusting it to be one: net-imap 0.6 answers
  # a rev2-capable server with an `ESearchResult`, which carries `each` and `to_a` and none
  # of `length`, `select` or `each_slice`. Gmail is rev1 so today it is a plain Array, but
  # the walk would break on the first server that is not -- at the progress line, before
  # anything it could report.
  def perform(&progress)
    @progress = progress || ->(*) {}
    imap = connect
    folders(imap).each do |folder|
      break if @stopped_by

      imap.examine(folder)
      @folder = folder
      @uidvalidity = imap.responses('UIDVALIDITY', &:last)
      uids = @cursor.unseen(folder, @uidvalidity, Array(imap.uid_search(@terms)))
      @progress.call(:folder, folder: folder, total: uids.length)
      walk(imap, uids)
    end
    self
  ensure
    @cursor.flush
    @importer.flush_search_index
    close(imap)
  end

  # What a stored mark means, and therefore what invalidates it.
  #
  # `BEFORE` is left out, and that is the whole of why this is not just `@terms`. It cuts
  # the newer end, so moving it in either direction never makes an older message newly
  # eligible -- and an older message hidden behind the mark is the only failure the stamp
  # exists to prevent. Left in, it would be worse than useless: the default cutoff is a
  # date, so it moves every midnight, and a run resumed the next day would find every mark
  # stale, start each folder at UID 0 and spend the whole day's provider budget re-walking
  # mail it has already declined. On a mailbox that takes weeks that is not a slow import,
  # it is an import that never finishes.
  #
  # `SINCE` is the opposite and stays: widening it backwards is exactly how older, lower
  # numbered mail becomes eligible under a mark that would hide it.
  #
  # The mailbox is part of the question too. `UIDVALIDITY` is unique inside one mailbox and
  # commonly starts at 1, so a channel repointed at a different account can present a fresh
  # folder whose stamp matches an old mark, and everything below it is filtered out before
  # the Message-ID check ever runs -- silently, since nothing errors.
  def selection
    [without_before(@terms), @kinds.sort, @attachments.key, @channel.imap_address, @channel.imap_login]
  end

  # The keyword and the date after it. `ALL` stands alone in the same list, so the pairs
  # cannot be sliced off blindly.
  def without_before(terms)
    at = terms.index('BEFORE')
    return terms if at.nil?

    terms[0...at] + terms[(at + 2)..].to_a
  end

  # Gmail is found by attribute; an ordinary server that advertises no special use is
  # walked from INBOX, which is the folder every server has. Without that fallback a
  # perfectly valid channel scans nothing at all -- or, if it happens to flag only its spam
  # folder, scans nothing but spam, which is worse because it looks like it worked.
  def folders(imap)
    return @folders if @folders.present?

    listed = imap.list('', '*') || []
    found = SPECIAL_ATTRS.index_with { |attr| listed.find { |f| f.attr.include?(attr) }&.name }
    @folders = [found[:All] || 'INBOX', found[:Junk]].compact
  end

  # EXAMINE rather than SELECT everywhere: read-only, so nothing this runs can mark
  # somebody's unread mail as seen or expunge anything.
  def connect
    imap = Net::IMAP.new(@channel.imap_address, port: @channel.imap_port, ssl: @channel.imap_enable_ssl, open_timeout: 30)
    Import::Email::Authentication.perform(imap, @channel)
    imap
  end

  def close(imap)
    return if imap.nil?

    imap.logout
  rescue Net::IMAP::Error
    imap.disconnect
  end

  private

  # The cursor moves to the highest UID this pass is done with, and no further. A batch
  # the loop ran out is considered whole, including the messages `unstored` filtered on the
  # way; a batch it stopped inside is considered only up to the last message handled, so
  # nothing above the stopping point is ever marked as read.
  #
  # And the mark stays there for the rest of the folder. The run carries on past a message
  # it could not settle, which is right -- one malformed part should not end a pass over
  # hundreds of thousands of messages -- but the batches after it are above the failure, so
  # letting them advance would bury the very UID the freeze exists to keep reachable. Every
  # later pass would then start above it and the message would be lost without an error
  # anywhere. The cost of freezing is re-reading headers already walked, which is cheap;
  # the cost of not freezing is a message.
  def walk(imap, uids)
    frozen = false
    uids.each_slice(HEADER_BATCH) do |batch|
      break if @stopped_by

      finished, mark = consume(imap, batch)
      # The batch boundary the walk already has is the one the index wants too: the
      # importer buffers a settlement at a time and something has to say when a run of them
      # is a batch.
      @importer.flush_search_index
      at = finished ? batch.last : mark
      unless frozen
        @cursor.advance(@folder, @uidvalidity, at) if at
        @cursor.flush
      end
      frozen ||= !finished
    end
  end

  # How far a batch got: the last UID it settled, and whether it settled all of them. The
  # mark freezes at the first message it could not settle, so nothing above that is ever
  # marked as read even though the run carries on past it.
  def consume(imap, batch)
    finished = true
    mark = nil
    unstored(imap, batch).each do |uid|
      if halt?
        finished = false
        break
      end

      @pacer.wait_for_room { |load| @progress.call(:paused, load: load) }
      handled = handle(imap, uid)
      mark = uid if handled && finished
      finished &&= handled
    end
    [finished, mark]
  end

  # Headers first, and cheap: a mailbox this size is walked many times over a run, and a
  # message the inbox already holds must not be paid for twice at full size.
  #
  # One query per batch rather than one per header. Every pass re-walks the whole mailbox
  # and asks about everything it has already filed, so an `exists?` per message is a round
  # trip per message for the life of the import -- hundreds of thousands of them before a
  # single byte is fetched, and they grow as the inbox fills.
  def unstored(imap, batch)
    heads = imap.uid_fetch(batch, 'BODY.PEEK[HEADER.FIELDS (MESSAGE-ID)]') || []
    seen = heads.to_h { |data| [data.attr['UID'], message_id_of(data)] }
    @stats[:sem_message_id] += seen.count { |_, id| id.blank? }
    wanted = seen.compact_blank
    stored = settled(wanted.values)
    @stats[:ja_importadas] += wanted.count { |_, id| stored.include?(id) }
    wanted.filter_map { |uid, id| uid unless stored.include?(id) }
  end

  # Which of these Message-IDs this run has nothing left to do about, which is not the same
  # as which ones are stored. A row filed by a pass that left its attachments behind is
  # stored and incomplete, and under a policy that now wants them it is work: skipping it
  # here is what would make the attachments unreachable, since no later pass ever looks at
  # a Message-ID this query has already answered for.
  #
  # Under the default the two questions coincide, and the query stays the one it was.
  def settled(ids)
    rows = @inbox.messages.where(source_id: ids)
    return rows.pluck(:source_id).to_set if @attachments.none?

    (rows.pluck(:source_id) - rework(rows).pluck(:source_id)).to_set
  end

  # Of the incomplete rows, the ones this run's policy would actually take attachments for.
  # Under a cutoff the older ones are not work: the importer declines them at
  # `skip_attachments?`, so calling them unsettled buys nothing and costs a full re-fetch of
  # the message -- on a mailbox where the byte budget is what ends the run, and where a
  # decade sits below any cutoff worth setting.
  #
  # `created_at` is the mail's own date, which `HistoryImporter` writes onto the row, so
  # this is the same comparison `skip?` makes. The one row the two read differently is one
  # whose headers carried no date at all: it is stored at the time of the import, which is
  # newer than any cutoff, so it is re-offered and declined on every pass. That was already
  # true before this and is bounded by how rare a mail with no Date header is.
  def rework(rows)
    incomplete = rows.where(Import::TEXT_ONLY_SQL)
    return incomplete if @attachments.all?

    incomplete.where(created_at: @attachments.cutoff..)
  end

  def message_id_of(data)
    Mail.read_from_string(data.attr['BODY[HEADER.FIELDS (MESSAGE-ID)]'].to_s).message_id
  rescue StandardError
    nil
  end

  def halt?
    @stopped_by = :orcamento if @pacer.over_budget?
    @stopped_by = :limite if @limit && (@stats[:importadas] + @stats[:enriquecidas]) >= @limit
    @stopped_by.present?
  end

  # Answers whether the message was settled one way or the other, which is what the cursor
  # is allowed to move past. A message that raised is not settled: left marked as read it
  # would be skipped by every later pass, so a transient failure -- a timeout, a malformed
  # part, a lock -- would quietly cost a message forever. The run keeps going past it; only
  # the mark stops.
  def handle(imap, uid)
    raw = @download.perform(imap, uid)
    return out_of_budget if @download.declined?
    return skip_empty if raw.blank?

    mail = Mail.read_from_string(raw)
    kind = classify(mail)
    @stats[:"visto_#{kind}"] += 1
    return true unless @kinds.include?(kind)

    @importer.import(mail, @channel, text_only: @download.lean?)
    @stats[@importer.outcome_kind] += 1
    @progress.call(:imported, kind: kind, stats: @stats)
    true
  rescue StandardError => e
    @stats[:erros] += 1
    @progress.call(:error, uid: uid, error: e)
    false
  end

  # A message larger than what is left of the budget. Not settled, so the mark stays below
  # it and the next run reaches it first; and the pass ends here rather than walking on in
  # search of something smaller, because ending a pass is what the budget is for. A run
  # that skipped every message it could not afford would spend the rest of a mailbox on
  # header fetches it has to repeat tomorrow anyway.
  def out_of_budget
    @stopped_by = :orcamento
    false
  end

  # A message the server had nothing to give for is settled, not failed: the mark may pass
  # it, and every later run would ask the same question and get the same nothing.
  def skip_empty
    @stats[:vazias] += 1
    true
  end

  def classify(mail)
    body = Import::Email::Body.new(MailPresenter.new(mail, @channel.account))
    Import::Email::Classifier.new(
      mail: mail, text: body[:full], reply: body[:reply], own_addresses: [@channel.email, @channel.imap_login]
    ).kind
  end
end
