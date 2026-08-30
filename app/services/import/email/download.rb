# How much of a message this run pulls off the server, and what that costs.
#
# Its own class because the decision is a policy with a price, not a step: `BODY.PEEK[]`
# pulls the encoded attachments along with the words, and the provider meters bytes over a
# rolling day, so what is asked for here is what ends a run early. The walk above is about
# where to look next and has none of this in it.
#
# Every branch spends through the pacer as it goes, so the budget is measured against what
# was actually transferred rather than against what was kept.
class Import::Email::Download
  # `lean?` answers the message just fetched: whether it went in without attachments it
  # actually has, which the importer records on the row so a later pass knows to come back.
  attr_reader :lean

  alias lean? lean

  # `declined?` answers the message just refused: too large for what is left of the budget,
  # so nothing was transferred and nothing was decided about it. The caller ends the pass
  # there and leaves its mark below the message, which is the whole point of refusing.
  attr_reader :declined

  alias declined? declined

  def initialize(pacer:, attachments:, stats:)
    @pacer = pacer
    @attachments = attachments
    @stats = stats
  end

  # The cutoff is decided before any of the message is downloaded, because the cost it
  # exists to control is paid at the fetch and nowhere else: a run that decides afterwards
  # has already spent its whole provider budget on the megabytes it then declines to keep.
  # The header and the structure are a few kilobytes and answer both questions -- when the
  # mail was sent, and whether it carries anything besides text.
  def perform(imap, uid)
    @lean = false
    @declined = false
    meta = imap.uid_fetch(uid, ['BODY.PEEK[HEADER]', 'BODYSTRUCTURE', 'RFC822.SIZE'])&.first
    return if meta.nil?

    header = meta.attr['BODY[HEADER]'].to_s
    @pacer.spend(header.bytesize)
    lean = Import::Email::TextOnly.new(meta.attr['BODYSTRUCTURE'])
    return whole(imap, uid, meta.attr['RFC822.SIZE']) unless text_only?(header, lean)

    text_only(imap, uid, header, lean)
  end

  private

  # The size arrives with the header and the structure, in the round trip already being
  # made, so asking what a message weighs costs nothing. Refusing here rather than letting
  # `over_budget?` notice afterwards is the difference between a ceiling and a ceiling plus
  # one message -- and the message that crosses it is exactly the kind this branch exists
  # for, the one carrying the attachments.
  #
  # A server that reports no size is fetched as it was. This sharpens the ceiling; it is
  # not a precondition for having one, and no mailbox is worth refusing to walk over it.
  def whole(imap, uid, size)
    return decline if size.to_i.positive? && !@pacer.room_for?(size.to_i)

    raw = imap.uid_fetch(uid, 'BODY.PEEK[]')&.first&.attr&.dig('BODY[]').to_s
    return if raw.blank?

    @pacer.spend(raw.bytesize)
    raw
  end

  def decline
    @declined = true
    nil
  end

  # Worth a second round trip only when the cutoff excludes this message's attachments and
  # it actually carries some.
  def text_only?(header, lean)
    @attachments.skip?(header_date(header)) && lean.attachments?
  end

  # Only ever reached when the cutoff excludes this message's attachments, which decides
  # what to do about a body it cannot find: nothing. Falling back to the whole message here
  # would download every attachment the policy just excluded and then discard them, which is
  # the one thing this path exists to prevent -- and on a message that is nothing but
  # attachments, the fallback is the entire message. The row goes in on its header alone,
  # marked as withholding what it has, so the pass that wants the files finds it.
  def text_only(imap, uid, header, lean)
    @stats[:sem_anexos] += 1
    @lean = true
    lean.rebuild(header, body_of(imap, uid, lean))
  end

  def body_of(imap, uid, lean)
    section = lean.part&.fetch(:section, nil)
    return '' if section.nil?

    body = imap.uid_fetch(uid, "BODY.PEEK[#{section}]")&.first&.attr&.dig("BODY[#{section}]").to_s
    @pacer.spend(body.bytesize)
    body
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
end
