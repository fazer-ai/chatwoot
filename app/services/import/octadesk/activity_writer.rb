# Writes the parts of a ticket's history that were never messages.
#
# Roughly half of an exported ticket's interactions carry no comment: they are the
# ticketing system recording that somebody took the thread, moved it between groups, or
# closed it. Dropping them leaves a transcript that never says who resolved anything,
# which for an archive built to be consulted is most of what a reader came for.
#
# So they become activity rows, the same kind Chatwoot writes for itself when a
# conversation is marked resolved. Kept apart from the message importer because the two
# have nothing in common but the conversation they attach to: one carries what a person
# said, the other what the system observed.
class Import::Octadesk::ActivityWriter
  # A trigger firing is not history anybody reads: "Gatilho executado: notificar o
  # solicitante" is the automation narrating itself.
  TRIGGER = 3

  def initialize(inbox:, stats:)
    @inbox = inbox
    @account = inbox.account
    @stats = stats
  end

  # Returns the rows it wrote, because the settlement has to see them: an activity carries
  # a date like any other row, and a settlement that took only the messages would put
  # `last_activity_at` in a different place than one that reads the thread back off the
  # database. The two must agree, or a re-run moves the stamp and the import stops being
  # something that can be repeated.
  def perform(conversation, ticket)
    Array(ticket['Interactions']).reject { |interaction| commented?(interaction) }
                                 .filter_map { |interaction| write(conversation, interaction) }
  end

  # Shared with the message importer, which selects on the opposite answer.
  def self.commented?(interaction)
    Array(interaction['Comments']).any? { |comment| comment['Content'].to_s.strip.present? }
  end

  # Whether this interaction would become an activity row, answered without writing one, so
  # a caller can tell a ticket carrying only status changes from one carrying nothing at
  # all. The first is history and belongs in the archive; only the second is empty.
  def self.writable?(interaction)
    !commented?(interaction) &&
      line_for(interaction['PropertiesChanges'] || {}, interaction['Person'] || {}).present?
  end

  # Only the two changes a reader of an archive asks about: where the thread went and who
  # took it. The rest of `PropertiesChanges` restates fields the conversation already
  # carries. On the class because it reads nothing but its arguments.
  def self.line_for(changes, person)
    return if person['Type'] == TRIGGER

    parts = []
    parts << "Status: #{changes['Status']}" if changes['Status'].present?
    parts << "Atribuido a #{changes['AssignedName']}" if changes['AssignedName'].present?
    return if parts.empty?

    who = person['Name'].to_s.squish.presence
    [parts.join(' - '), who && "(por #{who})"].compact.join(' ')
  end

  private

  def commented?(interaction) = self.class.commented?(interaction)

  def write(conversation, interaction)
    line = self.class.line_for(interaction['PropertiesChanges'] || {}, interaction['Person'] || {})
    return if line.blank?

    # One value, built once and used for both the check and the write: computing it twice
    # is how an importer ends up looking for a row it will not find and writing it again on
    # every pass.
    id = Import::Octadesk::Stream.oid(interaction['_id'])
    return if id.blank?

    source_id = "#{Import::Octadesk::TicketImporter::SOURCE_PREFIX}:#{id}:act"
    return if conversation.messages.exists?(source_id: source_id)

    row = conversation.messages.create!(
      account_id: @account.id, inbox_id: @inbox.id, source_id: source_id,
      message_type: :activity, content: line, content_attributes: { imported: true },
      created_at: Import::Octadesk::Stream.time(interaction['DateCreation']) || conversation.created_at
    )
    @stats[:atividades] += 1
    row
  end
end
