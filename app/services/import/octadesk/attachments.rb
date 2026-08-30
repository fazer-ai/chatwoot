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

    # Seeded from what is already on the message and added to as the loop goes, because an
    # interaction can list the same URL twice: read only from the snapshot, every copy after
    # the first is another download of a file we have just stored, on a run whose cost is
    # the downloads.
    held = stored_sources(message)
    permitted(interaction).each do |attachment|
      url = attachment['Url'].to_s
      next if url.blank?
      next if held.include?(url)

      stored = Import::Octadesk::AttachmentFetcher.new(message: message, url: url, name: attachment['Name']).perform
      held << url
      @stats[stored ? :anexos : :anexos_recusados] += 1
    rescue StandardError
      @stats[:anexos_falharam] += 1
    end
  end

  private

  # `Message` refuses more than fifteen and the mail pipeline trims to that before it
  # attaches anything; this had no cap at all. Trimmed before the fetch rather than left to
  # the model, because the cap is cheap to apply and expensive to hit: past the sixteenth
  # the bytes are spent on a download that produces a message the dashboard will not render.
  # The count is kept so a run says out loud what it left behind.
  def permitted(interaction)
    listed = Array(interaction['Attachments'])
    return listed if listed.length <= Message::NUMBER_OF_PERMITTED_ATTACHMENTS

    @stats[:anexos_acima_do_teto] += listed.length - Message::NUMBER_OF_PERMITTED_ATTACHMENTS
    listed.first(Message::NUMBER_OF_PERMITTED_ATTACHMENTS)
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
