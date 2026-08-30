# frozen_string_literal: true

require 'net/imap'

# Backfills an email inbox from IMAP. The loop lives in Import::Email::Backfill; this is
# the option parsing and the report around it.
#
# Written for a mailbox too big to take in one sitting: hundreds of thousands of messages
# and hundreds of gigabytes of attachments, behind a provider that allows 2.5 GB of IMAP
# download a day. So
# the run is resumable (it re-scans headers and skips what the inbox holds, keyed on
# Message-ID), paced (against a byte budget and the host's load average) and silent (every
# write inside Import::SilentWrite: no dashboard push, no automations, no outgoing
# webhooks, no notifications, so agents working the inbox see nothing appear).
#
#   INBOX_ID=1 bundle exec rails imap:scan               # dry run, writes nothing
#   INBOX_ID=1 LIMIT=200 bundle exec rails imap:import   # first real batch
#
# Options, all through the environment:
#   INBOX_ID           required
#   FOLDERS            comma separated (default: the all-mail folder plus Spam)
#   SINCE / UNTIL      IMAP dates, e.g. 01-Jan-2023
#   ATTACHMENTS        `all`, or a YYYY-MM-DD to take attachments only on messages newer
#                      than that date. Unset means none, which is what keeps a first pass
#                      inside the budget: an attachment is never fetched, not fetched and
#                      dropped, so the bytes are never spent
#   KINDS              comma separated, see Import::Email::Classifier (default: customer).
#                      `relay` can be scanned but not imported, see Backfill::UNIMPORTABLE
#   BUDGET_MB          IMAP bytes to spend before stopping (default 2000 of the 2500 allowed)
#   MAX_LOAD           pause while the host's 1-minute load is above this (default 2.5)
#   LIMIT              stop after importing this many messages
#   RESET_CURSOR       true/1 to forget how far previous passes got and walk from the start.
#                      The run is resumable because it remembers, per folder, the highest
#                      UID it has already looked at -- the inbox alone cannot say, since
#                      most of a support mailbox is read and declined rather than written
#   SAMPLE             imap:scan only, messages to classify per folder (default 400)
#   IMAP_DISABLED_OK   true/1 to run against a channel whose IMAP integration is off. Only
#                      for an archive inbox: it holds credentials on purpose and the live
#                      fetch job must stay away from the mailbox they open
module ImapImportOptions
  module_function

  def inbox!
    inbox = Inbox.find_by(id: ENV.fetch('INBOX_ID', nil))
    abort 'ERRO: defina INBOX_ID' if inbox.nil?
    abort "ERRO: inbox #{inbox.id} nao e um canal de e-mail" unless inbox.channel.is_a?(Channel::Email)
    imap!(inbox)

    inbox
  end

  # `imap_enabled` is the switch that stops Chatwoot from polling a mailbox, and connecting
  # anyway is spending credentials somebody turned off. Refused by default, the way the task
  # this replaces refused it: a disabled channel also carries settings nobody has kept
  # current, so what the run gets instead of a clear line here is a login error.
  #
  # Overridable, because an archive inbox is the one configuration where the switch and the
  # credentials mean different things. It holds real credentials for a mailbox the live
  # fetch job must never touch -- enabled, `Inboxes::FetchImapEmailsJob` would pull the same
  # mailbox into the same inbox alongside the import, and the history would arrive twice.
  # `IMAP_DISABLED_OK=1` is that setup stated out loud rather than assumed by an importer.
  def imap!(inbox)
    return if inbox.channel.imap_enabled?
    return if Import::Options.boolean('IMAP_DISABLED_OK')

    abort "ERRO: IMAP esta desligado no inbox #{inbox.id}. Ligue a integracao, ou passe " \
          'IMAP_DISABLED_OK=1 se a caixa e so de arquivo e o fetch do Chatwoot nao pode toca-la.'
  end

  def terms
    terms = ['ALL']
    terms = ['SINCE', ENV.fetch('SINCE')] if ENV['SINCE'].present?
    terms += ['BEFORE', ENV.fetch('UNTIL')] if ENV['UNTIL'].present?
    terms
  end

  def folders = ENV['FOLDERS'].presence&.split(',')&.map(&:strip)

  # Refused here rather than defaulted, because `KINDS=` is a setting somebody wrote on
  # purpose and it means nothing: the run would download and classify the whole mailbox,
  # import none of it, advance the cursor over all of it and report the folder finished.
  # An empty list is legitimate for `imap:scan`, which builds its own.
  def kinds
    given = (ENV['KINDS'] || 'customer').split(',').map(&:strip).compact_blank
    abort 'ERRO: KINDS esta vazio, nada seria importado' if given.empty?

    given
  end

  # Read strictly rather than cast: getting this wrong throws away the resume point on every
  # invocation, so each pass re-walks and re-downloads the declined mail it had already got
  # past, which on this mailbox is most of it.
  def reset_cursor? = Import::Options.boolean('RESET_CURSOR')

  # Read strictly, and read in the policy: a typo stops the run at the first line instead of
  # quietly reading as "none" and finishing without a single attachment.
  def attachments = Import::Email::AttachmentPolicy.from_setting(ENV['ATTACHMENTS'].presence)

  # Counts are integers and measurements are not: `SAMPLE=0.5` truncates to zero at the call
  # site and the scan classifies nothing while printing a finished projection. See
  # Import::Options for why none of these is read leniently.
  def limit = Import::Options.integer('LIMIT')
  def sample = Import::Options.integer('SAMPLE', default: 400)

  def pacer
    Import::Email::Pacer.new(budget_mb: Import::Options.decimal('BUDGET_MB', default: 2000),
                             max_load: Import::Options.decimal('MAX_LOAD', default: 2.5))
  end

  def duration(seconds)
    seconds = seconds.to_i
    return "#{seconds}s" if seconds < 60
    return "#{seconds / 60}m#{seconds % 60}s" if seconds < 3600

    "#{seconds / 3600}h#{(seconds % 3600) / 60}m"
  end

  # The one-line progress display, and the summary after it. Here rather than inside the
  # task body so the tasks stay short enough to read in one screen.
  def printer(pacer, started)
    lambda do |event, payload|
      case event
      when :folder then puts "\n#{payload[:folder]}: #{payload[:total]} candidatas"
      when :paused then print "\r  [pausa] load #{payload[:load]} acima do teto, aguardando...            "
      when :error then warn "\n  [ERRO] uid #{payload[:uid]}: #{payload[:error].class} #{payload[:error].message}"
      when :imported then print_progress(payload[:stats], pacer, started)
      end
    end
  end

  def print_progress(stats, pacer, started)
    skipped = stats.sum { |key, value| key.to_s.start_with?('visto_') ? value : 0 } - stats[:importadas]
    enriched = stats[:enriquecidas].positive? ? "#{stats[:enriquecidas]} anexadas | " : ''
    print "\r  #{stats[:importadas]} importadas | #{enriched}#{skipped} puladas | #{pacer.spent_mb}MB | " \
          "load #{pacer.load_average} | #{duration(Time.zone.now - started)}        "
  end

  def report(run, pacer, started)
    puts "\n#{'=' * 70}"
    puts case run.stopped_by
         when :orcamento then 'Parou no teto de bytes. Rode de novo amanha para continuar.'
         when :limite then 'Parou no LIMIT. Rode de novo para continuar.'
         else 'Pastas esgotadas.'
         end
    run.stats.sort.each { |key, value| puts "  #{key.to_s.ljust(20)} #{value}" }
    puts "  #{'baixado'.ljust(20)} #{pacer.spent_mb} MB"
    puts "  #{'tempo'.ljust(20)} #{duration(Time.zone.now - started)} (pausado #{duration(pacer.paused_for)})"
  end

  # Classifies a sample of a folder.
  # Charged against the same budget the import spends, and stopped by it. A scan reads whole
  # messages to classify them, so a sample that lands on attachments costs gigabytes -- and
  # the provider lockout a dry run triggers is the same one `BUDGET_MB` exists to avoid,
  # only harder to explain because nothing was written.
  # One message at a time, and the budget asked before each. A scan reads whole messages to
  # classify them, so a batch of fifty lands fifty complete bodies -- attachments and all --
  # before anything can be charged for them, which on this mailbox is the difference between
  # a margin and a lockout. The sample is a few hundred messages, so the round trips cost
  # nothing worth the risk.
  # Returns the tally and whether it is the tally that was asked for. A sample cut short by
  # the budget is not a smaller sample, it is a different claim: the projection multiplies
  # it out over the whole folder either way, and one large first message can end up
  # describing a mailbox from a single result.
  def sample_kinds(imap, run, uids, sample, pacer)
    kinds = Hash.new(0)
    wanted = spread(uids, sample)
    wanted.each do |uid|
      break if pacer.over_budget?

      kinds[sample_kind(imap, run, uid, pacer)] += 1
    end
    [kinds, kinds.values.sum == wanted.length]
  end

  # Spread across the folder rather than the newest N, because the shape of a mailbox
  # changes over years and its tail does not describe it.
  # `sample` uids spread evenly across the folder, and never more than `sample`.
  #
  # Not `each_slice(length / sample)`: integer division makes that stride 1 for any folder
  # between `sample + 1` and `2 * sample - 1` messages, so the scan takes every uid in it --
  # `SAMPLE=400` over 799 messages downloads 799 whole messages, close to double the cap it
  # was given, against the same byte budget the import is rationing.
  #
  # Stepping by a float keeps the count exact. The step is at least 1 whenever the folder is
  # larger than the sample, so the indices strictly increase and no uid is picked twice.
  def spread(uids, sample)
    return uids if uids.length <= sample

    step = uids.length / sample.to_f
    Array.new(sample) { |index| uids[(index * step).floor] }
  end

  def sample_kind(imap, run, uid, pacer)
    raw = imap.uid_fetch(uid, 'BODY.PEEK[]')&.first&.attr&.dig('BODY[]').to_s
    return :vazia if raw.blank?

    pacer.spend(raw.bytesize)
    run.send(:classify, Mail.read_from_string(raw))
  rescue StandardError
    :erro
  end
end

# What the two tasks print. Its own module because a report is not a setting: these read
# nothing from the environment and decide nothing about the run, and keeping them beside
# the option readers was what pushed that module past its size.
module ImapImportReport
  module_function

  def header(inbox, extra = {})
    puts "Inbox:   #{inbox.name} (##{inbox.id})  #{inbox.channel.email}"
    extra.each { |k, v| puts "#{"#{k}:".ljust(9)}#{v}" }
    puts '-' * 70
  end

  # A projection built on the folders that fit is not a smaller projection, it is a wrong
  # one: the folder with the attachments is the one that exhausts the budget, and the one
  # whose absence the total does not show. So the gap is named rather than left to a reader
  # of a table that looks complete.
  def projection(totals, unsampled)
    puts "\n#{'=' * 70}\nPROJECAO GERAL#{unsampled.any? ? ' (PARCIAL)' : ''}"
    totals.sort_by { |_, count| -count }.each { |kind, count| puts "  #{kind.to_s.ljust(12)} ~#{count}" }
    return if unsampled.empty?

    puts "\nORCAMENTO ESGOTADO em: #{unsampled.map { |folder, how| "#{folder} (#{how})" }.join(', ')}."
    puts 'A projecao acima extrapola de menos amostra do que foi pedida, ou de nenhuma.'
    puts 'Rode de novo amanha ou com BUDGET_MB maior.'
  end
end

namespace :imap do # rubocop:disable Metrics/BlockLength -- two task bodies in one namespace
  desc 'Dry run: classifica uma amostra do que imap:import faria, sem escrever nada'
  task scan: :environment do
    inbox = ImapImportOptions.inbox!
    sample = ImapImportOptions.sample
    pacer = ImapImportOptions.pacer
    run = Import::Email::Backfill.new(inbox: inbox, kinds: [], pacer: pacer,
                                      folders: ImapImportOptions.folders, terms: ImapImportOptions.terms)
    imap = run.connect
    ImapImportReport.header(inbox, Pastas: run.folders(imap).join(', '), Amostra: "#{sample} por pasta",
                                   Teto: "#{pacer.budget_mb_left}MB")

    totals = Hash.new(0)
    unsampled = []
    run.folders(imap).each do |folder|
      # A scan that ran out of budget in an early folder samples nothing in the later ones,
      # and a projection built on that is not a smaller projection, it is a wrong one: the
      # folder with the attachments is exactly the one that exhausts the budget, and exactly
      # the one whose absence the total does not show. Named here rather than left to the
      # reader of a table that looks complete.
      next unsampled << [folder, 'nenhuma amostra'] if pacer.over_budget?

      imap.examine(folder)
      uids = Array(imap.uid_search(ImapImportOptions.terms))
      puts "\n#{folder}: #{uids.length} mensagens"
      next if uids.empty?

      kinds, whole = ImapImportOptions.sample_kinds(imap, run, uids, sample, pacer)
      unsampled << [folder, 'amostra parcial'] unless whole
      seen = kinds.values.sum
      next if seen.zero?

      kinds.sort_by { |_, v| -v }.each do |kind, count|
        projected = (uids.length * count / seen.to_f).round
        totals[kind] += projected
        puts "   #{kind.to_s.ljust(10)} #{count}/#{seen} (#{(100.0 * count / seen).round(1)}%)  -> ~#{projected}"
      end
    end
    run.close(imap)

    ImapImportReport.projection(totals, unsampled)
  end

  desc 'Importa historico de e-mails do IMAP para uma inbox do Chatwoot'
  task import: :environment do
    inbox = ImapImportOptions.inbox!
    pacer = ImapImportOptions.pacer
    started = Time.zone.now
    attachments = ImapImportOptions.attachments

    ImapImportReport.header(
      inbox,
      Tipos: ImapImportOptions.kinds.join(', '),
      Anexos: attachments.to_s,
      Teto: "#{pacer.budget_mb_left}MB, load maximo #{ENV['MAX_LOAD'] || 2.5}",
      Limite: ImapImportOptions.limit || 'sem limite'
    )

    run = Import::Email::Backfill.new(
      inbox: inbox, kinds: ImapImportOptions.kinds, pacer: pacer,
      folders: ImapImportOptions.folders, terms: ImapImportOptions.terms,
      attachments: attachments, limit: ImapImportOptions.limit
    )
    run.cursor.reset if ImapImportOptions.reset_cursor?
    puts "Retoma:  #{run.cursor}"
    puts '-' * 70

    run.perform(&ImapImportOptions.printer(pacer, started))
    ImapImportOptions.report(run, pacer, started)
  end
end
