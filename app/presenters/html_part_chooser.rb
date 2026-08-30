# Which `text/html` part of a message carries what the sender wrote.
#
# Its own class because it is a policy with a cost, not a step. `Mail::Message#html_part`
# answers with the first `text/html` it meets in a depth-first walk, which is right almost
# always and silently wrong on a shape iOS Mail produces: a `multipart/alternative` whose
# one child is a `multipart/mixed`, holding a stub of a hundred-odd bytes, then the
# attachment, then the part the customer actually wrote. The stub renders to nothing, so
# the message reaches the agent as an empty bubble under a subject -- no error, no
# attachment missing, just no words.
class HtmlPartChooser
  def self.for(mail) = new(mail).perform

  def initialize(mail)
    @mail = mail
  end

  # The gem's answer stands unless there is a choice to make and its answer says nothing,
  # so every message whose first part is the real one keeps the part it has today. That
  # restraint is the point: taking the largest outright would prefer a quoted forward over
  # the short reply written above it, which is a worse failure than the one being fixed and
  # a far more common shape.
  #
  # The two cheap tests come before the expensive one on purpose. This sits on every inbound
  # email and answering it costs a full parse, so the parse is reached only by a message
  # that actually carries rival parts.
  def perform
    chosen = @mail.html_part
    rivals = body_parts.select { |part| part.mime_type == 'text/html' }
    return chosen if chosen.nil? || rivals.length < 2 || rendered(chosen).present?

    rivals.max_by { |part| rendered(part).length } || chosen
  end

  private

  # The parts of the message itself, which is not every part it carries. An attached
  # document has parts of its own, and a `text/html` inside one reads, to a flat walk,
  # exactly like a candidate. It is not one, and preferring it because it is longer than the
  # reply above it is precisely the failure this class exists to avoid.
  #
  # `attachment?` alone does not answer where to stop: it is a question about a file, a
  # disposition plus a name, and the container holding an attached document has no name. A
  # `multipart/related` carrying `Content-Disposition: attachment` answers false while every
  # leaf under it is attached content. Reading the disposition as well is what makes the
  # walk stop at the top of that subtree rather than one level inside it.
  def body_parts(part = @mail, found = [])
    part.parts.each do |child|
      next if attached?(child)

      found << child
      body_parts(child, found) if child.multipart?
    end
    found
  end

  def attached?(part)
    part.attachment? || part.content_disposition.to_s.strip.downcase.start_with?('attachment')
  rescue StandardError
    false
  end

  # What a part is worth to a reader, which is the same question the caller asks of it a
  # moment later. A part that is only markup answers with nothing.
  def rendered(part)
    ::HtmlParser.parse_reply(part.body.decoded.to_s).to_s
  rescue StandardError
    ''
  end
end
