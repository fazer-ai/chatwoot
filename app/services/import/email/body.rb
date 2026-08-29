# The words a message carries, whichever part is carrying them.
#
# Plain text when the message has it, the HTML stripped of its tags when it does not, and
# empty when it has neither. Two readings, and the classifier needs both: `:full` is
# everything the message carries and `:reply` is the same body with the quoted history
# trimmed away.
#
# Its own class because both halves are easy to get half right. Reading only `text_content`
# files every HTML-only message as empty, which on a mailbox written by a ticketing system
# is most of the machine mail; reading the whole body rather than the reply classifies a
# customer's answer as the template they quoted.
#
# And because the reading has to be translated. `MailPresenter` names its keys the other
# way round: `text_content[:reply]` is `mail_content(text_part)`, byte for byte the same
# value it returns for `:full`, while the result of `EmailReplyTrimmer.trim` is filed under
# `:quoted`. The html pair is the same shape -- `:reply` is the parsed body and `:quoted` is
# that body trimmed. So asking the presenter for `:reply` gets the untrimmed message and
# quietly undoes the whole point. Upstream's names, our meaning, in one place.
class Import::Email::Body
  # What we call it, and the key it actually lives under.
  KEYS = { full: :full, reply: :quoted }.freeze

  def initialize(presenter)
    @presenter = presenter
  end

  def [](part)
    key = KEYS.fetch(part)
    text(key).presence || stripped_html(key)
  end

  private

  def text(key) = (@presenter.text_content.presence && @presenter.text_content[key]).to_s

  def stripped_html(key)
    ActionView::Base.full_sanitizer.sanitize((@presenter.html_content.presence && @presenter.html_content[key]).to_s)
  end
end
