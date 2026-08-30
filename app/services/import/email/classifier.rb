# What a message in an imported mailbox actually is.
#
# A support mailbox that sat behind a ticketing system is not a transcript. Measured on
# one such mailbox, better than a quarter of it was written by the ticketing system
# rather than by a person, in three shapes that want three different answers, and the
# shapes are not separable by sender: the same `From` carries a receipt, an alert and an
# agent's reply.
#
#   receipt        "Sua solicitação NNNN foi recebida e está sendo analisada". Fixed
#                  text plus a re-quote of what the customer already sent. Nothing of its
#                  own, and the customer's own email is in the mailbox beside it.
#   alert          "Chegou um novo ticket NNNN que não foi atribuído para nenhum agente",
#                  quoting the customer. By definition no agent has answered yet, so it
#                  carries no reply -- but 3% of them quote a customer whose message came
#                  in through another channel and exists nowhere else, which is why the
#                  caller decides this one against the inbox rather than here.
#   sent           the mailbox writing, not being written to. Not a shape at all -- it is
#                  read off `From` -- but it belongs in the same answer, because Gmail's
#                  \All folder is the union of everything except Spam and Trash and
#                  therefore holds the Sent folder whole. A fifth of the messages on this
#                  mailbox are its own.
#   relay          "Por favor acesse o octadesk e verifique essa solicitação. Seguem mais
#                  informações abaixo: <nome> 21/09/2023 13:30 Olá. Tudo bem? Para
#                  cancelamento...". The wrapper is machinery and the payload is a reply
#                  the ticketing system sent over its own SMTP, so for some threads this
#                  notification is the only copy the mailbox holds of it. Recognised so a
#                  scan can count it and a run can leave it out, and no further: the name
#                  above the payload is whoever spoke last, an agent on some threads and
#                  the customer on others, and nothing in the wrapper tells them apart.
#                  See Import::Email::Backfill::UNIMPORTABLE.
#
# Everything else is a person writing to the company, which is the ordinary case and the
# one the mail pipeline was built for.
class Import::Email::Classifier
  # Matched against text that has been folded to unaccented ASCII first, so the patterns
  # are written without accents and stay readable. Folding rather than a wildcard per
  # accented letter, because this mailbox does not agree with itself about how to spell
  # one: the same sentence arrives as `solicitação`, as `solicita&ccedil;&atilde;o`, and
  # as `solicitac&#807;a&#771;o` -- a base letter followed by a combining mark, encoded as
  # a numeric entity. The last form is why a pattern like `solicita..o` silently stops
  # matching: after unescaping, `ç` and `ã` are each two codepoints, not one.
  RECEIPT = /mensagem automatica|solicitacao\s*\d+\s*foi recebida|sendo analisada por nossa equipe/i
  ALERT   = /chegou um novo ticket|nao foi atribuido para nenhum agente/i
  RELAY   = /acesse o octadesk e verifique|seguem mais informacoes abaixo/i
  CSAT    = /pesquisa de satisfacao|avalie o atendimento/i

  # The ticketing system's own number, which is what the operators searched by for four
  # years and the only key that ties a thread here to a row in the export. In the subject
  # as a trailing `#NNNN`, in the body as `ticket NNNN`.
  TICKET_SUBJECT = /#(\d{2,9})\s*\z/
  TICKET_BODY    = /\bticket\s+(\d{2,9})\b/i

  # A body this short says nothing a reader would want.
  MIN_CONTENT = 40

  # Every answer this class gives. Exported so a caller can refuse a kind it does not
  # recognise before it connects to anything: a typo in `KINDS` otherwise matches nothing,
  # imports nothing, advances the cursor over the whole mailbox and reports it as done.
  KINDS = %i[sent receipt csat alert relay empty customer].freeze

  # Kinds a scan counts and a run may not take, because the importer files everything
  # through the incoming mailbox pipeline and neither of these is incoming.
  #
  # `sent` is the mailbox's own outgoing mail. It matters more than it looks: Gmail's \All
  # is the union of everything except Spam and Trash, so it contains the Sent folder whole,
  # which on a long-lived support mailbox is a sizeable share of every message in it. Run
  # through the pipeline each one invents a contact for the company's own address and files
  # the company's own words as something a customer wrote.
  #
  # `relay` is the ticketing system writing to the mailbox about a reply it sent elsewhere.
  # The words inside are typed by whoever spoke last: an agent on some threads, the
  # customer on others, with nothing in the notification that separates the two.
  #
  # Both are recognised rather than hidden, so a scan reports what a run is leaving behind.
  UNIMPORTABLE = %i[sent relay].freeze

  # The kinds a run may take, or an exception naming what is wrong with the list. Refused
  # before anything connects, because both mistakes are silent at run time: an unknown kind
  # matches nothing, so the run downloads and classifies the whole mailbox, imports none of
  # it, advances the cursor over all of it and reports the folder finished.
  #
  # An empty list is legitimate and means "classify, import nothing", which is what a scan
  # asks for.
  def self.importable!(kinds)
    asked = Array(kinds).map(&:to_sym)
    unknown = asked - KINDS
    raise ArgumentError, "unknown kinds: #{unknown.join(', ')}" if unknown.any?

    refused = asked & UNIMPORTABLE
    raise ArgumentError, "these kinds cannot be imported: #{refused.join(', ')}" if refused.any?

    asked
  end

  attr_reader :kind, :ticket

  # `own_addresses` are the mailbox's own, and they are what separates a message the company
  # received from one it sent. Optional, because a caller that does not pass any simply
  # never sees the `sent` kind.
  #
  # Plural because a channel routinely has two. The address the inbox publishes and the one
  # it authenticates as are separate columns and differ on legacy Google aliases and on
  # Microsoft UPN setups, and it is the login that owns the Sent copies. Matching on the
  # published address alone reads those as customer mail -- and since \All contains Sent
  # whole, a default run would file the company's own replies as things customers wrote.
  #
  # `reply` is the body with the quoted history trimmed off, and the kind is read from it
  # rather than from the whole. A customer answering a receipt, a CSAT request or an alert
  # quotes the thing they are answering, so the whole body carries the template's own
  # phrases and the message is classified as the machine mail it is a reply to -- which
  # under the default `KINDS=customer` drops the customer's words and moves the cursor past
  # them. The machine mail itself is unaffected: a receipt's fixed text is the unquoted top
  # of it, which is exactly what survives the trim.
  #
  # The ticket number is still read from the whole body, because it usually lives in the
  # part that was quoted.
  def initialize(mail:, text:, reply: nil, own_addresses: nil)
    @mail = mail
    @own_addresses = Array(own_addresses).map { |address| address.to_s.downcase.strip }.compact_blank.to_set
    @text = self.class.fold(text)
    @reply = self.class.fold(reply).presence || @text
    classify
  end

  # Entities decoded, then decomposed and stripped of combining marks, so every spelling
  # of the same sentence folds to the same ASCII.
  #
  # Decoded rather than blanked: replacing `&#807;` with a space is what splits
  # `solicitação` into `solicitac a o`. Through Nokogiri rather than CGI.unescapeHTML,
  # which only knows the five XML entities and leaves `&ccedil;` standing. Twice, because
  # these templates are routinely double-encoded (`&amp;#xE7;`), and guarded on `&` so the
  # parse is only paid for when there is something to decode.
  def self.fold(text)
    decoded = text.to_s
    2.times { decoded = Nokogiri::HTML::DocumentFragment.parse(decoded).text if decoded.include?('&') }
    decoded.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').gsub(/\s+/, ' ').strip
  rescue ArgumentError, Encoding::CompatibilityError
    # Mail that lies about its charset. Better a crude fold than a dropped message.
    decoded.to_s.encode('UTF-8', invalid: :replace, undef: :replace, replace: '').gsub(/\s+/, ' ').strip
  end

  def skip? = %i[receipt csat empty].include?(kind)
  def relay? = kind == :relay
  def alert? = kind == :alert

  private

  def classify
    @ticket = extract_ticket
    @kind = kind_of_text
  end

  # Sender first, because it settles the question the text cannot: a copy of an outgoing
  # reply reads exactly like the customer mail it quotes.
  def kind_of_text
    return :sent if own_mail?
    return :receipt if RECEIPT.match?(@reply)
    return :csat if CSAT.match?(@reply)
    return :alert if ALERT.match?(@reply)
    return :relay if RELAY.match?(@reply)
    return :empty if @text.length < MIN_CONTENT

    :customer
  end

  # From one of our addresses, and not sent on somebody else's behalf.
  #
  # The exception is not exotic: a website form posts as the company and points `Reply-To`
  # at the customer, so `From` is ours and the message is inbound. Read on `From` alone it
  # answers `:sent`, which a run refuses outright -- so every message the form ever
  # generated is dropped and the cursor moves past it. `HistoryImporter#redirected_reply_to?`
  # already reads this shape to name the contact; the classifier has to agree with it or
  # those messages never reach the importer at all.
  #
  # A `Reply-To` that is also ours is a real outgoing mail with a routing header, so the
  # test is that it points somewhere else.
  def own_mail?
    return false if @own_addresses.empty?
    return false unless Array(@mail.from).any? { |address| ours?(address) }

    reply_to = Array(@mail.reply_to)
    reply_to.empty? || reply_to.any? { |address| ours?(address) }
  end

  def ours?(address) = @own_addresses.include?(address.to_s.downcase.strip)

  def extract_ticket
    @mail.subject.to_s[TICKET_SUBJECT, 1] || @text[TICKET_BODY, 1]
  end
end
