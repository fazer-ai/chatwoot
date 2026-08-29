# Files one exported OctaDesk ticket as a Chatwoot conversation.
#
# Unlike the IMAP importer, this one does not run the live mail pipeline, because there is
# no mail to run: the export is the ticketing system's own model, already parsed, already
# threaded, already attributed. Rebuilding an RFC822 document from it so the mailbox could
# take it apart again would be inventing a worse copy of data we already have structured.
#
# What the export settles that a mailbox could not:
#
#   direction     `Person.Type == 1` is an agent. Measured over 20k tickets: 94% of those
#                 carry the company's own mail domain, and the rest are an escalation bot
#                 plus a couple of agents on personal Gmail. Everything else is the
#                 customer. Reconstructing this from the mailbox meant reading
#                 notification wrappers and guessing from name frequency.
#   who wrote it  `Person.Name` and `Person.Email`, so an agent reply carries the agent.
#   the thread    `Interactions` is already the conversation, in order, so nothing depends
#                 on In-Reply-To surviving four years of forwarding.
#   identity      `RequesterMail` is the real customer on some 98% of tickets. The rest
#                 came through the website form, which carries the company address there
#                 instead and the customer's own address inside the first comment,
#                 recoverable on nearly all of them.
#
# Idempotent on two keys, because a run over gigabytes will be interrupted: the conversation
# is found by ticket number, and each message by the interaction's Mongo id. Re-running
# costs a lookup per record and writes nothing twice.
class Import::Octadesk::TicketImporter
  include Import::HistorySettlement

  SOURCE_PREFIX = 'octadesk'.freeze
  EMAIL_IN_BODY = /(?:^|\s)e-?mail:\s*([^\s,;<>()]+@[^\s,;<>()]+)/i
  NAME_IN_BODY = /(?:^|\s)nome:\s*(.{2,80}?)\s*(?:\n|e-?mail:|fone:|telefone:|cidade:|\z)/i

  attr_reader :opened, :stats

  # `form_address` and `form_sender_name` are the address and display name the company's
  # website form posts as. They are deployment-specific, so they are given rather than
  # assumed: with neither set, every ticket is taken at its stated requester and the
  # recovery below simply never fires.
  def initialize(inbox:, attachments: false, form_address: nil, form_sender_name: nil)
    @inbox = inbox
    @account = inbox.account
    @attachments = attachments
    @form_address = form_address.to_s.downcase.strip.presence
    @form_local = @form_address&.split('@')&.first
    @form_sender_name = form_sender_name.to_s.strip.presence
    @opened = Set.new
    @stats = Hash.new(0)
  end

  def import(ticket)
    interactions = writable(ticket)
    return @stats[:sem_conteudo] += 1 if interactions.empty?

    Import::SilentWrite.wrap do
      contact_inbox = resolve_contact(ticket, interactions)
      return @stats[:sem_contato] += 1 if contact_inbox.nil?

      conversation = conversation_for(ticket, contact_inbox)
      rows = interactions.filter_map { |interaction| write(conversation, contact_inbox.contact, interaction) }
      activity_writer.perform(conversation, ticket)
      settle(rows, []) if rows.any?
      @stats[:tickets] += 1
    end
  end

  private

  # Only the two changes a reader of an archive cares about. A person of type 3 is a
  # trigger, and "Gatilho executado: notificar o solicitante" is machinery, not an event.
  def activity_line(changes, person)
    return if person['Type'] == 3

    parts = []
    parts << "Status: #{changes['Status']}" if changes['Status'].present?
    parts << "Atribuído a #{changes['AssignedName']}" if changes['AssignedName'].present?
    return if parts.empty?

    who = person['Name'].to_s.squish.presence
    [parts.join(' · '), who && "(por #{who})"].compact.join(' ')
  end

  # An interaction with no comment is a status change or a trigger firing: real history,
  # but not a message. Those are written separately by Import::Octadesk::ActivityWriter.
  def writable(ticket)
    Array(ticket['Interactions']).select { |i| Import::Octadesk::ActivityWriter.commented?(i) }
  end

  def resolve_contact(ticket, interactions)
    email = customer_email(ticket, interactions)
    return if email.blank?

    name = contact_name(ticket, email, interactions)
    existing = @inbox.contacts.from_email(email)
    return ContactInbox.find_by(inbox: @inbox, contact: existing) || build_contact(email, name) if existing

    build_contact(email, name)
  end

  # The website form posts as the company with the customer named in the body. Same shape
  # the mailbox showed, and the same fix: take the address out of the text.
  def customer_email(ticket, interactions)
    stated = ticket['RequesterMail'].to_s.downcase.strip
    return stated if stated.present? && stated != @form_address

    from_body = interactions.first(2).flat_map { |i| Array(i['Comments']).map { |c| c['Content'].to_s } }
                            .join(' ')[EMAIL_IN_BODY, 1].to_s.downcase
    from_body.presence || stated.presence
  end

  def build_contact(email, name)
    ::ContactInboxWithContactBuilder.new(
      source_id: email, inbox: @inbox, contact_attributes: { name: name, email: email }
    ).perform
  end

  # The form tickets name the company rather than the person, so the requester name is
  # only trusted when it is not that. What the form does carry is a `Nome:` line in the
  # body beside the `Email:` one, which is the person's own name and better than the local
  # part of their address.
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

  # Dated to the ticket and resolved from the start, never resolved afterwards: born in
  # that state it fires no resolution event and writes no "resolved by" line, where a
  # transition would do both and file every imported thread into today's figures.
  def conversation_for(ticket, contact_inbox)
    number = ticket['Number'].to_s
    existing = find_by_ticket(number)
    return existing if existing

    opened_at = Import::Octadesk::Stream.time(ticket['DateCreation'])
    conversation = ::Conversation.create!(
      account_id: @account.id, inbox_id: @inbox.id,
      contact_id: contact_inbox.contact_id, contact_inbox_id: contact_inbox.id,
      status: :resolved, created_at: opened_at || Time.current,
      additional_attributes: { source: 'email', mail_subject: subject(ticket) }.compact,
      custom_attributes: ticket_attributes(ticket, number)
    )
    @opened << conversation.id
    apply_tags(conversation, ticket)
    stamp_resolution(conversation, ticket)
    conversation
  end

  # The thread is created resolved rather than resolved afterwards, so the column that
  # would normally record when that happened is stamped by hand. Written with
  # `update_columns` for the same reason everything else here is: a save would wake the
  # callbacks the import exists to keep quiet.
  def stamp_resolution(conversation, ticket)
    done = Import::Octadesk::Stream.time(ticket['DoneDate'])
    return if done.blank?

    conversation.update_columns(status_changed_at: done) # rubocop:disable Rails/SkipsModelValidations
  end

  # What the ticketing system knew about the thread and Chatwoot has no column for. Kept
  # as custom attributes rather than dropped, because this inbox exists to be searched: the
  # ticket number is what the operators looked things up by for four years, and the agent
  # who handled it is what a report by agent would otherwise have no way to ask about.
  #
  # The agent is a name and an address, not an assignee. Assigning would need these people
  # to be members of the archive account, and inventing seats for former staff to make a
  # closed thread look assigned is a worse trade than a searchable attribute. It also keeps
  # the archive out of everybody's queue, which is the point of importing it resolved.
  def ticket_attributes(ticket, number)
    {
      SOURCE_PREFIX => number,
      "#{SOURCE_PREFIX}_agent" => ticket['AssignedName'].to_s.squish.presence,
      "#{SOURCE_PREFIX}_agent_email" => ticket['AssignedMail'].to_s.downcase.presence,
      "#{SOURCE_PREFIX}_form" => ticket.dig('Form', 'Name').to_s.presence,
      "#{SOURCE_PREFIX}_status" => ticket['CurrentStatusName'].to_s.presence
    }.compact_blank
  end

  # A ticket whose summary is the whole first email, which some of them are: the column is
  # jsonb with a 1500 character rule per key, and a subject long enough to break it is not
  # a subject anybody reads to the end anyway.
  def subject(ticket)
    ticket['Summary'].to_s.squish.presence&.truncate(1_400)
  end

  # The number the operators searched by for four years, and the only key that ties a
  # thread here back to a row in the export.
  def find_by_ticket(number)
    return if number.blank?

    @inbox.conversations.where('custom_attributes ->> ? = ?', SOURCE_PREFIX, number).first
  end

  def apply_tags(conversation, ticket)
    tags = Array(ticket['Tags']).filter_map { |tag| tag.is_a?(Hash) ? tag['Name'] : tag }.compact_blank
    conversation.add_labels(tags) if tags.any?
  rescue StandardError
    @stats[:tags_recusadas] += 1
  end

  def write(conversation, contact, interaction)
    source_id = message_source_id(interaction)
    return if source_id.blank?
    return skip(:ja_tinha) if conversation.messages.exists?(source_id: source_id)

    person = interaction['Person'] || {}
    message = conversation.messages.create!(message_attributes(conversation, contact, interaction, person, source_id))
    attach(message, interaction)
    @stats[person['Type'] == 1 ? :respostas : :mensagens] += 1
    message
  end

  def message_attributes(conversation, contact, interaction, person, source_id)
    agent = person['Type'] == 1
    {
      account_id: @account.id, inbox_id: @inbox.id, source_id: source_id,
      message_type: agent ? :outgoing : :incoming,
      content: body(interaction), content_type: :incoming_email,
      sender: agent ? nil : contact,
      created_at: Import::Octadesk::Stream.time(interaction['DateCreation']) || conversation.created_at,
      content_attributes: content_attributes(person, agent)
    }
  end

  def message_source_id(interaction)
    id = Import::Octadesk::Stream.oid(interaction['_id'])
    "#{SOURCE_PREFIX}:#{id}" if id.present?
  end

  # Counts a record the run declined to write and yields nil, so the caller's
  # `filter_map` drops it. Written out because `stats[key] += 1 && nil` reads like it
  # does this and does not: `&&` binds tighter than `+=`, so it adds nil and raises.
  def skip(key)
    @stats[key] += 1
    nil
  end

  def body(interaction)
    Array(interaction['Comments']).filter_map { |comment| comment['Content'].to_s.strip.presence }.join("\n\n")
  end

  # `imported` is what Inbound::Coverage and HistorySettlement read, and what a report
  # excluding backfilled traffic filters on. The agent is kept as plain data rather than
  # resolved to a User: most of these people were never Chatwoot users, and inventing
  # accounts for them would put names in the agent list that cannot log in.
  def content_attributes(person, agent)
    attributes = { imported: true }
    return attributes unless agent

    attributes.merge(imported_agent: { name: person['Name'], email: person['Email'] }.compact_blank)
  end

  # Attachments live as public URLs on the vendor's bucket, which stops existing when the
  # subscription does. Fetching them here is both the import and the mirror: Active Storage
  # writes the copy to our own S3.
  def attach(message, interaction)
    return unless @attachments

    Array(interaction['Attachments']).each do |attachment|
      url = attachment['Url'].to_s
      next if url.blank?

      Import::Octadesk::AttachmentFetcher.new(message: message, url: url, name: attachment['Name']).perform
      @stats[:anexos] += 1
    rescue StandardError
      @stats[:anexos_falharam] += 1
    end
  end

  # No screen is watching a bulk backfill, so the settlement's announce hook is a plain
  # yield. See Import::SilentWrite.
  def activity_writer = @activity_writer ||= Import::Octadesk::ActivityWriter.new(inbox: @inbox, stats: @stats)

  def announcing(&) = yield
end
