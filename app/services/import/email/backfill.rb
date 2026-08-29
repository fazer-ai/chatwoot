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

  attr_reader :stats, :pacer, :stopped_by

  # rubocop:disable Metrics/ParameterLists -- every one of these is an independent knob on
  # a run that is meant to be started, stopped and restarted with different settings; an
  # options object would only move the list one file over.
  def initialize(inbox:, kinds:, pacer:, folders: nil, terms: ['ALL'], attachments_since: nil, limit: nil)
    @inbox = inbox
    @channel = inbox.channel
    @kinds = Array(kinds).map(&:to_sym)
    @pacer = pacer
    @folders = folders
    @terms = terms
    @limit = limit
    @importer = Import::Email::HistoryImporter.new(attachments_since: attachments_since)
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

  def folders(imap)
    return @folders if @folders.present?

    listed = imap.list('', '*') || []
    @folders = SPECIAL_ATTRS.filter_map { |attr| listed.find { |f| f.attr.include?(attr) }&.name }
  end

  # EXAMINE rather than SELECT everywhere: read-only, so nothing this runs can mark
  # somebody's unread mail as seen or expunge anything.
  def connect
    imap = Net::IMAP.new(@channel.imap_address, port: @channel.imap_port, ssl: @channel.imap_enable_ssl, open_timeout: 30)
    Imap::Authentication.authenticate!(imap, @channel.imap_authentication || 'plain', @channel.imap_login, @channel.imap_password)
    imap
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
  def unstored(imap, batch)
    heads = imap.uid_fetch(batch, 'BODY.PEEK[HEADER.FIELDS (MESSAGE-ID)]') || []
    heads.filter_map do |data|
      id = Mail.read_from_string(data.attr['BODY[HEADER.FIELDS (MESSAGE-ID)]'].to_s).message_id
      next skip(:sem_message_id) if id.blank?
      next skip(:ja_importadas) if @inbox.messages.exists?(source_id: id)

      data.attr['UID']
    end
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

  def fetch(imap, uid)
    raw = imap.uid_fetch(uid, 'BODY.PEEK[]')&.first&.attr&.dig('BODY[]').to_s
    return skip(:vazias) if raw.blank?

    @pacer.spend(raw.bytesize)
    raw
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
    Import::Email::Classifier.new(mail: mail, text: text).kind
  end
end
