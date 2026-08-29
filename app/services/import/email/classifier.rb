# What a message in an imported mailbox actually is.
#
# A support mailbox that sat behind a ticketing system is not a transcript. Measured on
# one such mailbox, a bit over a quarter of it was written by the ticketing system
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

  attr_reader :kind, :ticket

  def initialize(mail:, text:)
    @mail = mail
    @text = self.class.fold(text)
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

  def kind_of_text
    return :receipt if RECEIPT.match?(@text)
    return :csat if CSAT.match?(@text)
    return :alert if ALERT.match?(@text)
    return :relay if RELAY.match?(@text)
    return :empty if @text.length < MIN_CONTENT

    :customer
  end

  def extract_ticket
    @mail.subject.to_s[TICKET_SUBJECT, 1] || @text[TICKET_BODY, 1]
  end
end
