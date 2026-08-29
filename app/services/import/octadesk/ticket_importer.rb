# Files one exported OctaDesk ticket as a Chatwoot conversation.
#
# Unlike the IMAP importer, this one does not run the live mail pipeline, because there is
# no mail to run: the export is the ticketing system's own model, already parsed, already
# threaded, already attributed. Rebuilding an RFC822 document from it so the mailbox could
# take it apart again would be inventing a worse copy of data we already have structured.
#
# What the export settles that a mailbox could not:
#
#   direction     `Person.Type == 1` is an agent. Measured over the export: nearly all of those
#                 carry the company's own mail domain, and the rest are an escalation bot
#                 plus a handful of individual senders. Everything else is the
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

  attr_reader :opened, :stats

  def initialize(inbox:, attachments: false, form_address: nil, form_sender_name: nil)
    @inbox = inbox
    @account = inbox.account
    @attachments = attachments
    @contacts = Import::Octadesk::ContactResolver.new(
      inbox: inbox, form_address: form_address, form_sender_name: form_sender_name
    )
    @opened = Set.new
    @stats = Hash.new(0)
  end

  def import(ticket)
    interactions = writable(ticket)
    return @stats[:sem_conteudo] += 1 if interactions.empty?

    Import::SilentWrite.wrap do
      contact_inbox = @contacts.perform(ticket, interactions)
      return @stats[:sem_contato] += 1 if contact_inbox.nil?

      conversation = conversation_for(ticket, contact_inbox)
      rows = interactions.filter_map { |interaction| write(conversation, contact_inbox.contact, interaction) }
      rows += activity_writer.perform(conversation, ticket)
      settle_ticket(conversation, rows)
      @stats[:tickets] += 1
    end
  end

  private

  # Settled from what the conversation holds, not from what this pass happened to write.
  # A run that stops between the message insert and the settlement leaves the rows on disk
  # and the stamps unset, and the next pass writes nothing because every source id is
  # already there -- so keying the settlement on "did I write something" would leave that
  # thread wrong forever, which is the one case resumability exists for.
  #
  # The conversation is put back in `opened` on that path, because it is: a thread carrying
  # nothing but imported rows still wears the stamps its creation left behind, and those
  # describe the interrupted run rather than the ticket. The test is the same one
  # `stamp_seen` makes, and for the same reason -- a thread that ever took live traffic has
  # real stamps, and overwriting those would be the worse error.
  def settle_ticket(conversation, rows)
    stored = rows.presence || conversation.messages.to_a
    return if stored.empty?

    @opened << conversation.id if resumed?(conversation)
    settle(stored, [])
  end

  # A conversation this run did not create still wears the stamps of the run that did, and
  # those describe the import rather than the ticket -- so it has to take the batch outright
  # the same way a new one does. This covers both interruption points: after the rows were
  # written and before they were, since a run that stops between `conversation_for` and the
  # first insert leaves a thread whose `last_activity_at` is newer than every row the next
  # pass writes, which the monotonic guard would then refuse to move.
  #
  # The test is the one `stamp_seen` makes: a thread that ever took live traffic has real
  # stamps, and overwriting those would be the worse error.
  def resumed?(conversation)
    return false if @opened.include?(conversation.id)

    conversation.messages.where.not(Import::IMPORTED_SQL).none?
  end

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
      status: :resolved, created_at: opened_at || Time.current, identifier: identifier_for(number),
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
  #
  # Read off `identifier`, which is indexed, rather than out of the JSON column, which is
  # not: at half a million tickets an unindexed expression lookup once per record scans an
  # inbox that grows as the run goes, and the import turns quadratic somewhere in the
  # middle of it. The number is written to both -- `custom_attributes` is what an operator
  # searches and a report groups by, `identifier` is what this lookup needs. The column is
  # otherwise unused on an email inbox.
  def identifier_for(number) = "#{SOURCE_PREFIX}:#{number}"

  def find_by_ticket(number)
    return if number.blank?

    @inbox.conversations.find_by(identifier: identifier_for(number))
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
      content_attributes: content_attributes(person, agent),
      additional_attributes: agent ? sender_name(person) : {}
    }
  end

  # An outgoing message with no sender and no `sender_name` renders as the bot, so every
  # agent reply in the archive would be attributed to one. `additional_attributes` is the
  # contract the message component already reads for exactly this case, which is what makes
  # it right here: the agent is a name on a historical row, not a seat somebody holds.
  def sender_name(person)
    name = person['Name'].to_s.squish.presence
    name ? { sender_name: name } : {}
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

      stored = Import::Octadesk::AttachmentFetcher.new(message: message, url: url, name: attachment['Name']).perform
      @stats[stored ? :anexos : :anexos_recusados] += 1
    rescue StandardError
      @stats[:anexos_falharam] += 1
    end
  end

  # No screen is watching a bulk backfill, so the settlement's announce hook is a plain
  # yield. See Import::SilentWrite.
  def activity_writer = @activity_writer ||= Import::Octadesk::ActivityWriter.new(inbox: @inbox, stats: @stats)

  def announcing(&) = yield
end
