# Walks the exported ticket collection and files what it finds.
#
# Built to be stopped, like its IMAP counterpart, but for a different reason: there is no
# provider budget here, only gigabytes of JSON and a live box that must not feel it. So the
# pacing is entirely the host's load average, and resuming is free because both keys the
# importer writes on -- the ticket number and the interaction id -- already say what has
# been filed.
#
# Parts are walked in order and the position is reported, so an interrupted run can be
# resumed from a part rather than from the beginning. That is a convenience, not a
# correctness requirement: starting over writes nothing twice, it only re-reads.
class Import::Octadesk::Backfill
  attr_reader :stats, :stopped_by

  # rubocop:disable Metrics/ParameterLists -- independent knobs on a run meant to be
  # started and restarted with different settings; an options object only moves the list.
  def initialize(inbox:, zip_path:, pacer:, attachments: false, limit: nil, from_part: nil,
                 form_address: nil, form_sender_name: nil)
    @stream = Import::Octadesk::Stream.new(zip_path)
    @pacer = pacer
    @limit = limit
    @from_part = from_part
    @importer = Import::Octadesk::TicketImporter.new(
      inbox: inbox, attachments: attachments,
      form_address: form_address, form_sender_name: form_sender_name
    )
    @stats = Hash.new(0)
    @stopped_by = nil
  end
  # rubocop:enable Metrics/ParameterLists

  def perform(&progress)
    @progress = progress || ->(*) {}
    parts.each do |part|
      break if @stopped_by

      @progress.call(:part, part: part)
      walk(part)
    end
    self
  end

  def parts
    all = @stream.parts
    return all if @from_part.blank?

    all.drop_while { |part| part < @from_part }
  end

  private

  def walk(part)
    @stream.each_object(part) do |ticket|
      raise StopIteration if halt?

      @pacer.wait_for_room { |load| @progress.call(:paused, load: load) }
      handle(ticket)
    end
  end

  def halt?
    @stopped_by = :limite if @limit && @stats[:lidos] >= @limit
    @stopped_by.present?
  end

  def handle(ticket)
    @stats[:lidos] += 1
    @importer.import(ticket)
    @progress.call(:ticket, stats: merged_stats)
  rescue StandardError => e
    @stats[:erros] += 1
    @progress.call(:error, ticket: ticket['Number'], error: e)
  end

  # The importer keeps its own tally of what it wrote; the walker keeps the tally of what
  # it read. Reported as one thing because the difference between them is the interesting
  # number: tickets read that produced nothing.
  def merged_stats = @stats.merge(@importer.stats)
end
