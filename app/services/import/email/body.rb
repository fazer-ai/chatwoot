# The words a message carries, whichever part is carrying them.
#
# Plain text when the message has it, the HTML stripped of its tags when it does not, and
# empty when it has neither. Two readings, and the classifier needs both: `:full` is
# everything the message carries and `:reply` is the same body with the quoted history
# trimmed away.
#
# Its own class because the fallback is the whole point and it is easy to get half right.
# Reading only `text_content` files every HTML-only message as empty, which on a mailbox
# written by a ticketing system is most of the machine mail; reading only the `:full` part
# classifies a customer's answer as the template they quoted.
class Import::Email::Body
  def initialize(presenter)
    @presenter = presenter
  end

  def [](part)
    text(part).presence || stripped_html(part)
  end

  private

  def text(part) = (@presenter.text_content.presence && @presenter.text_content[part]).to_s

  def stripped_html(part)
    ActionView::Base.full_sanitizer.sanitize((@presenter.html_content.presence && @presenter.html_content[part]).to_s)
  end
end
