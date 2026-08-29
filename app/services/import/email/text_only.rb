# The text-only version of a message, worked out from its `BODYSTRUCTURE` alone.
#
# Exists so the backfill can decide what a message costs before it downloads any of it.
# `BODY.PEEK[]` pulls the encoded attachments along with the words, so a run that fetches
# whole messages and drops the attachments afterwards has already spent the provider
# budget the cutoff was written to protect. The structure is a few hundred bytes and says
# where the words are.
#
# What comes back from `rebuild` is a smaller true copy: the message's own headers, so the
# dedupe key and the threading are untouched, and one text part standing in for the body,
# announced by its own Content-Type so the pipeline parses it as the single-part message it
# now is.
class Import::Email::TextOnly
  # Below this a text part is treated as saying nothing. A message written in HTML alone
  # still carries a `text/plain` alternative and it is routinely an empty stub of two
  # octets, so preferring plain by subtype alone picks the stub and files the message with
  # no body at all. `BODYSTRUCTURE` reports each part's octets, so the test costs nothing.
  MIN_PART_OCTETS = 32

  # Replaced by the standing-in part's own.
  DROPPED_HEADERS = /\A(content-type|content-transfer-encoding):/i

  def initialize(structure)
    @structure = structure
  end

  # Nothing to save on a message that is only text: both fetches cost the same bytes and
  # one of them costs an extra round trip.
  def attachments?
    leaves.any? { |part, _| !text?(part) }
  end

  # Plain when it says anything, the largest text part otherwise, and nil when even that is
  # under the floor -- the caller then takes the whole message, which is cheap to do and
  # always holds the words somewhere.
  def part
    @part ||= begin
      chosen = preferred_plain || texts.max_by { |candidate, _| candidate.size.to_i }
      describe(*chosen) if chosen && chosen.first.size.to_i >= MIN_PART_OCTETS
    end
  end

  # The message's own headers with the two that described the multipart envelope replaced.
  # Split on a newline that no whitespace follows, so a folded header stays one entry and
  # is dropped or kept whole.
  def rebuild(header, body)
    kept = header.split(/\r?\n(?![ \t])/).grep_v(DROPPED_HEADERS)
    kept << "Content-Type: #{[part[:type], part[:charset] && "charset=#{part[:charset]}"].compact.join('; ')}"
    kept << "Content-Transfer-Encoding: #{part[:encoding]}" if part[:encoding].present?
    "#{kept.join("\r\n").rstrip}\r\n\r\n#{body}"
  end

  private

  def texts = leaves.select { |candidate, _| text?(candidate) }

  def preferred_plain
    texts.find { |candidate, _| candidate.subtype.to_s.casecmp('PLAIN').zero? && candidate.size.to_i >= MIN_PART_OCTETS }
  end

  def describe(chosen, section)
    { section: section, encoding: chosen.encoding,
      type: "#{chosen.media_type.to_s.downcase}/#{chosen.subtype.to_s.downcase}",
      charset: chosen.param&.[]('CHARSET') }
  end

  # Text offered as a file is an attachment whatever its media type says: a .csv or a
  # quoted .eml is exactly the weight the cutoff means to leave behind.
  def text?(candidate)
    return false unless candidate.media_type.to_s.casecmp('TEXT').zero?

    (candidate.disposition&.dsp_type).to_s.casecmp('ATTACHMENT') != 0
  end

  # `BODYSTRUCTURE` is a tree: a multipart carries `parts`, a leaf carries its own media
  # type, and sections are numbered the way `BODY[n.m]` addresses them. A single-part
  # message has no parts and its body is section 1.
  def leaves = @leaves ||= walk(@structure, [])

  def walk(node, prefix)
    return [[node, (prefix.presence || [1]).join('.')]] unless node.respond_to?(:parts) && node.parts.present?

    node.parts.each_with_index.flat_map { |child, index| walk(child, prefix + [index + 1]) }
  end
end
