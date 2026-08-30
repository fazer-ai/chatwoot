# What one interaction's files owe one message, and the fetching of them.
#
# Its own class because it is a policy rather than a step: which of the listed URLs this
# message still needs, how many of them a message may hold, and what a run reports about
# the ones it did not take. The ticket importer asks once per interaction and does not
# carry any of it.
#
# The vendor's URLs are public and die with the subscription, so a file missed here is
# missed permanently rather than late. That is what makes every rule in this class about
# not spending a download twice and not spending one that cannot land.
class Import::Octadesk::Attachments
  def initialize(enabled:, stats:)
    @enabled = enabled
    @stats = stats
  end

  def perform(message, interaction)
    return unless @enabled

    wanted(interaction, stored_sources(message)).each do |attachment|
      stored = Import::Octadesk::AttachmentFetcher.new(
        message: message, url: attachment['Url'].to_s, name: attachment['Name']
      ).perform
      @stats[stored ? :anexos : :anexos_recusados] += 1
    rescue StandardError
      @stats[:anexos_falharam] += 1
    end
  end

  private

  # The files this message still needs, in the order the vendor listed them, and no more of
  # them than it has room for.
  #
  # Everything that is not a candidate is dropped before the cap rather than after, which is
  # the whole of the ordering here. A blank entry or a URL listed twice among the first
  # fifteen would otherwise spend a slot, and the real file sitting at position sixteen is
  # then never attempted -- not on this pass and not on any later one, because every pass
  # reads the same list the same way. The message ends up holding fewer than the permitted
  # number and still missing a file, which is the shape of a bug nobody goes looking for.
  #
  # `held` is both the filter and the arithmetic: what a previous pass already stored is not
  # work, and it is also room already spent.
  def wanted(interaction, held)
    listed = Array(interaction['Attachments'])
             .select { |attachment| attachment['Url'].to_s.present? }
             .uniq { |attachment| attachment['Url'].to_s }
             .reject { |attachment| held.include?(attachment['Url'].to_s) }
    room = [Message::NUMBER_OF_PERMITTED_ATTACHMENTS - held.size, 0].max
    return listed if listed.length <= room

    @stats[:anexos_acima_do_teto] += listed.length - room
    listed.first(room)
  end

  # Keyed on the source URL kept in the blob's metadata rather than on the filename: two
  # different files under one name is ordinary, and keyed on the name the copy that got
  # through would call the copy that did not done.
  #
  # A message this pass has just created holds nothing, and asking the association would be
  # a query per message over the whole export.
  def stored_sources(message)
    return Set.new if message.previously_new_record?

    message.attachments.filter_map { |a| a.file.blob&.metadata&.dig('import_source') if a.file.attached? }.to_set
  end
end
