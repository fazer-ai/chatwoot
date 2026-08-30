# Who an exported ticket is from.
#
# Straightforward on most of them -- `RequesterMail` and `RequesterName` are the customer
# and that is the end of it. The exception is the company's own website form, which posts
# as the company and names the person in the body of the first comment, so a ticket that
# came through it would otherwise file every customer under one contact with the company's
# address and the company's name.
#
# Both form values are deployment-specific, so they are given rather than assumed: with
# neither set the recovery never fires and every ticket is taken at its stated requester.
class Import::Octadesk::ContactResolver
  EMAIL_IN_BODY = /(?:^|\s)e-?mail:\s*([^\s,;<>()]+@[^\s,;<>()]+)/i
  NAME_IN_BODY = /(?:^|\s)nome:\s*(.{2,80}?)\s*(?:\n|e-?mail:|fone:|telefone:|cidade:|\z)/i

  def initialize(inbox:, form_address: nil, form_sender_name: nil)
    @inbox = inbox
    @form_address = form_address.to_s.downcase.strip.presence
    @form_local = @form_address&.split('@')&.first
    @form_sender_name = form_sender_name.to_s.strip.presence
  end

  # Returns the ContactInbox, or nil when the ticket names nobody at all.
  def perform(ticket, interactions)
    email = customer_email(ticket, interactions)
    return if email.blank?

    name = contact_name(ticket, email, interactions)
    existing = @inbox.contacts.from_email(email)
    return ContactInbox.find_by(inbox: @inbox, contact: existing) || build(email, name) if existing

    build(email, name)
  end

  private

  # The form posts as the company with the customer's address in the text, so that is where
  # it is taken from.
  def customer_email(ticket, interactions)
    stated = ticket['RequesterMail'].to_s.downcase.strip
    return stated if stated.present? && stated != @form_address
    return stated.presence unless configured?

    from_body = interactions.first(2).flat_map { |i| Array(i['Comments']).map { |c| c['Content'].to_s } }
                            .join(' ')[EMAIL_IN_BODY, 1].to_s.downcase
    from_body.presence || stated.presence
  end

  # Reading an address out of a comment is only ever right for a deployment that has a form
  # posting as itself. Ungated it fires on any ticket with no stated requester, and an
  # `Email: ...` line in the text is as likely to be somebody the customer is writing
  # about -- a colleague, a supplier, the address on an invoice -- as the customer. Filing
  # the thread under that person is worse than filing it under nobody, which is what the
  # caller counts and reports.
  def configured? = @form_address.present? || @form_sender_name.present?

  # Form tickets name the company rather than the person, so the stated name is trusted
  # only when it is not that. What the form does carry is a `Nome:` line beside the
  # `Email:` one, which is the person's own name and better than the local part of an
  # address.
  def contact_name(ticket, email, interactions)
    stated = ticket['RequesterName'].to_s.strip
    return stated if stated.present? && !form_sender?(stated)

    body(interactions.first).to_s[NAME_IN_BODY, 1].to_s.squish.presence || email.split('@').first
  end

  # The two ways an export spells "this is the form, not the person": the display name the
  # form posts under, and the local part of the address it posts from, which the exporter
  # also uses as a name on its own.
  def form_sender?(stated)
    return true if @form_sender_name && stated.casecmp(@form_sender_name).zero?

    @form_local.present? && stated.downcase.include?(@form_local)
  end

  def body(interaction)
    Array(interaction&.dig('Comments')).map { |comment| comment['Content'].to_s }.join("\n")
  end

  def build(email, name)
    ::ContactInboxWithContactBuilder.new(
      source_id: email, inbox: @inbox, contact_attributes: { name: name, email: email }
    ).perform
  end
end
