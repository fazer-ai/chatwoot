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
    @cursor = Import::Email::Cursor.new(@channel, selection: [@terms, @kinds.sort, @attachments.key])
    @stats = Hash.new(0)
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
    close(imap)
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
    rows = rows.where.not(Import::TEXT_ONLY_SQL) unless @attachments.none?
    rows.pluck(:source_id).to_set
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
    raw = fetch(imap, uid)
    return true if raw.blank?

    mail = Mail.read_from_string(raw)
    kind = classify(mail)
    @stats[:"visto_#{kind}"] += 1
    return true unless @kinds.include?(kind)

    @importer.import(mail, @channel, text_only: @lean)
    @stats[@importer.outcome_kind] += 1
    @progress.call(:imported, kind: kind, stats: @stats)
    true
  rescue StandardError => e
    @stats[:erros] += 1
    @progress.call(:error, uid: uid, error: e)
    false
  end

  # The cutoff is decided before any of the message is downloaded, because the cost it
  # exists to control is paid at the fetch and nowhere else: `BODY.PEEK[]` pulls the
  # encoded attachments along with the words, so a run that decides afterwards has already
  # spent its whole provider budget on the megabytes it then declines to keep. The header
  # and the structure are a few kilobytes and answer both questions -- when the mail was
  # sent, and whether it carries anything besides text.
  def fetch(imap, uid)
    @lean = false
    meta = imap.uid_fetch(uid, ['BODY.PEEK[HEADER]', 'BODYSTRUCTURE'])&.first
    return skip(:vazias) if meta.nil?

    header = meta.attr['BODY[HEADER]'].to_s
    @pacer.spend(header.bytesize)
    lean = Import::Email::TextOnly.new(meta.attr['BODYSTRUCTURE'])
    return whole(imap, uid) unless text_only?(header, lean)

    text_only(imap, uid, header, lean) || whole(imap, uid)
  end

  def whole(imap, uid)
    raw = imap.uid_fetch(uid, 'BODY.PEEK[]')&.first&.attr&.dig('BODY[]').to_s
    return skip(:vazias) if raw.blank?

    @pacer.spend(raw.bytesize)
    raw
  end

  # Worth a second round trip only when the cutoff excludes this message's attachments and
  # it actually carries some.
  def text_only?(header, lean)
    @attachments.skip?(header_date(header)) && lean.attachments?
  end

  # Returns nil when the structure names no text part worth taking, and the caller falls
  # back to the whole message: a body that cannot be located is not a body worth guessing.
  def text_only(imap, uid, header, lean)
    part = lean.part
    return if part.nil?

    section = part[:section]
    body = imap.uid_fetch(uid, "BODY.PEEK[#{section}]")&.first&.attr&.dig("BODY[#{section}]").to_s
    return if body.blank?

    @pacer.spend(body.bytesize)
    @stats[:sem_anexos] += 1
    @lean = true
    lean.rebuild(header, body)
  end

  # The same reading the importer will take of the same message. A header carries its
  # `Received` lines too, so the fallback is available here and has to be used: deciding the
  # cutoff on `Date` alone strips the attachments off every mail with an unreadable one,
  # including the mail the fallback would have placed inside the window.
  def header_date(header)
    Import::Email::Timestamp.of(Mail.read_from_string(header))
  rescue StandardError
    nil
  end

  # Counts a record the run declined to write and yields nil, so the caller's
  # `filter_map` drops it. Written out because `stats[key] += 1 && nil` reads like it
  # does this and does not: `&&` binds tighter than `+=`, so it adds nil and raises.
  def skip(key)
    @stats[key] += 1
    nil
  end

  def classify(mail)
    body = Import::Email::Body.new(MailPresenter.new(mail, @channel.account))
    Import::Email::Classifier.new(
      mail: mail, text: body[:full], reply: body[:reply], own_addresses: [@channel.email, @channel.imap_login]
    ).kind
  end
end
