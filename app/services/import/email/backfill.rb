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

  # Kinds a scan counts and a run may not take, because this importer files everything
  # through the incoming mailbox pipeline and neither of these is incoming.
  #
  # `sent` is the mailbox's own outgoing mail. It matters more than it looks: Gmail's \All
  # is the union of everything except Spam and Trash, so it contains the Sent folder
  # whole -- measured on one support mailbox, about a fifth of it.
  # Run through the pipeline each one invents a contact for the company's own address and
  # files the company's own words as something a customer wrote.
  #
  # `relay` is the ticketing system writing to the mailbox about a reply it sent elsewhere.
  # The words inside are typed by whoever spoke last: an agent on some threads, the customer
  # on others, with nothing in the notification that separates the two.
  #
  # Both are recognised rather than hidden, so a scan reports what a run is leaving behind.
  UNIMPORTABLE = %i[sent relay].freeze

  attr_reader :stats, :pacer, :stopped_by

  # rubocop:disable Metrics/ParameterLists -- every one of these is an independent knob on
  # a run that is meant to be started, stopped and restarted with different settings; an
  # options object would only move the list one file over.
  def initialize(inbox:, kinds:, pacer:, folders: nil, terms: ['ALL'], attachments: nil, limit: nil)
    @inbox = inbox
    @channel = inbox.channel
    @kinds = Array(kinds).map(&:to_sym)
    refused = @kinds & UNIMPORTABLE
    raise ArgumentError, "these kinds cannot be imported: #{refused.join(', ')}" if refused.any?

    @pacer = pacer
    @folders = folders
    @terms = terms
    @limit = limit
    @attachments = Import::Email::AttachmentPolicy.build(attachments)
    @importer = Import::Email::HistoryImporter.new(attachments: @attachments)
    @stats = Hash.new(0)
    @stopped_by = nil
  end
  # rubocop:enable Metrics/ParameterLists

  # `progress` is called with (event, payload) as the run goes: :folder, :paused,
  # :imported, :error. Held on the instance rather than threaded through every frame,
  # because the loop is three levels deep and passing a block down all of them says
  # nothing about what the loop does.
  def perform(&progress)
    @progress = progress || ->(*) {}
    imap = connect
    folders(imap).each do |folder|
      break if @stopped_by

      imap.examine(folder)
      uids = imap.uid_search(@terms)
      @progress.call(:folder, folder: folder, total: uids.length)
      walk(imap, uids)
    end
    self
  ensure
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
    authenticate(imap)
    imap
  end

  # The same three cases the live fetch services split into, because a channel does not
  # stop being an OAuth channel when a rake task is the one connecting: on Google and
  # Microsoft the stored `imap_password` is empty or stale and only a refreshed XOAUTH2
  # token authenticates, so reading the column would fail every run against those
  # providers with nothing but a login error to say why.
  def authenticate(imap)
    case @channel.provider
    when 'google'
      imap.authenticate('XOAUTH2', @channel.imap_login, Google::RefreshOauthTokenService.new(channel: @channel).access_token)
    when 'microsoft'
      imap.authenticate('XOAUTH2', @channel.imap_login, Microsoft::RefreshOauthTokenService.new(channel: @channel).access_token)
    else
      Imap::Authentication.authenticate!(imap, @channel.imap_authentication, @channel.imap_login, @channel.imap_password)
    end
  end

  def close(imap)
    return if imap.nil?

    imap.logout
  rescue Net::IMAP::Error
    imap.disconnect
  end

  private

  def walk(imap, uids)
    uids.each_slice(HEADER_BATCH) do |batch|
      break if @stopped_by

      unstored(imap, batch).each do |uid|
        break if halt?

        @pacer.wait_for_room { |load| @progress.call(:paused, load: load) }
        handle(imap, uid)
      end
    end
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
    stored = @inbox.messages.where(source_id: wanted.values).pluck(:source_id).to_set
    @stats[:ja_importadas] += wanted.count { |_, id| stored.include?(id) }
    wanted.filter_map { |uid, id| uid unless stored.include?(id) }
  end

  def message_id_of(data)
    Mail.read_from_string(data.attr['BODY[HEADER.FIELDS (MESSAGE-ID)]'].to_s).message_id
  rescue StandardError
    nil
  end

  def halt?
    @stopped_by = :orcamento if @pacer.over_budget?
    @stopped_by = :limite if @limit && @stats[:importadas] >= @limit
    @stopped_by.present?
  end

  def handle(imap, uid)
    raw = fetch(imap, uid)
    return if raw.blank?

    mail = Mail.read_from_string(raw)
    kind = classify(mail)
    @stats[:"visto_#{kind}"] += 1
    return unless @kinds.include?(kind)

    @stats[@importer.import(mail, @channel) ? :importadas : :recusadas] += 1
    @progress.call(:imported, kind: kind, stats: @stats)
  rescue StandardError => e
    @stats[:erros] += 1
    @progress.call(:error, uid: uid, error: e)
  end

  # The cutoff is decided before any of the message is downloaded, because the cost it
  # exists to control is paid at the fetch and nowhere else: `BODY.PEEK[]` pulls the
  # encoded attachments along with the words, so a run that decides afterwards has already
  # spent its whole provider budget on the megabytes it then declines to keep. The header
  # and the structure are a few kilobytes and answer both questions -- when the mail was
  # sent, and whether it carries anything besides text.
  def fetch(imap, uid)
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
    lean.rebuild(header, body)
  end

  def header_date(header)
    Mail.read_from_string(header).date&.to_time
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
    presenter = MailPresenter.new(mail, @channel.account)
    text = (presenter.text_content.presence && presenter.text_content[:full]).presence ||
           ActionView::Base.full_sanitizer.sanitize((presenter.html_content.presence && presenter.html_content[:full]).to_s)
    Import::Email::Classifier.new(mail: mail, text: text, own_address: @channel.email).kind
  end
end
