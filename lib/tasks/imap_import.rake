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
#   RESET_CURSOR       1 to forget how far previous passes got and walk from the start.
#                      The run is resumable because it remembers, per folder, the highest
#                      UID it has already looked at -- the inbox alone cannot say, since
#                      most of a support mailbox is read and declined rather than written
#   SAMPLE             imap:scan only, messages to classify per folder (default 400)
module ImapImportOptions
  module_function

  def inbox!
    inbox = Inbox.find_by(id: ENV.fetch('INBOX_ID', nil))
    abort 'ERRO: defina INBOX_ID' if inbox.nil?
    abort "ERRO: inbox #{inbox.id} nao e um canal de e-mail" unless inbox.channel.is_a?(Channel::Email)

    inbox
  end

  def terms
    terms = ['ALL']
    terms = ['SINCE', ENV.fetch('SINCE')] if ENV['SINCE'].present?
    terms += ['BEFORE', ENV.fetch('UNTIL')] if ENV['UNTIL'].present?
    terms
  end

  def folders = ENV['FOLDERS'].presence&.split(',')&.map(&:strip)
  def kinds = (ENV['KINDS'] || 'customer').split(',').map(&:strip)

  # `all`, a date, or nothing at all. Parsed here so a typo stops the run at the first line
  # instead of quietly reading as "none" and finishing without a single attachment.
  def attachments
    raw = ENV['ATTACHMENTS'].presence
    return Import::Email::AttachmentPolicy.build(nil) if raw.nil?
    return Import::Email::AttachmentPolicy.build(raw) if raw.casecmp('all').zero?

    parsed = Time.zone.parse(raw)
    raise ArgumentError, "ATTACHMENTS: use `all` or a date (YYYY-MM-DD), got #{raw.inspect}" if parsed.nil?

    Import::Email::AttachmentPolicy.build(parsed)
  end

  def limit = ENV['LIMIT'].presence&.to_i
  def pacer = Import::Email::Pacer.new(budget_mb: ENV['BUDGET_MB'] || 2000, max_load: ENV['MAX_LOAD'] || 2.5)

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
    print "\r  #{stats[:importadas]} importadas | #{skipped} puladas | #{pacer.spent_mb}MB | " \
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
  def sample_kinds(imap, run, uids, sample, pacer)
    kinds = Hash.new(0)
    spread(uids, sample).each do |uid|
      break if pacer.over_budget?

      kinds[sample_kind(imap, run, uid, pacer)] += 1
    end
    kinds
  end

  # Spread across the folder rather than the newest N, because the shape of a mailbox
  # changes over years and its tail does not describe it.
  def spread(uids, sample) = uids.each_slice([uids.length / sample, 1].max).map(&:first)

  def sample_kind(imap, run, uid, pacer)
    raw = imap.uid_fetch(uid, 'BODY.PEEK[]')&.first&.attr&.dig('BODY[]').to_s
    return :vazia if raw.blank?

    pacer.spend(raw.bytesize)
    run.send(:classify, Mail.read_from_string(raw))
  rescue StandardError
    :erro
  end

  def header(inbox, extra = {})
    puts "Inbox:   #{inbox.name} (##{inbox.id})  #{inbox.channel.email}"
    extra.each { |k, v| puts "#{"#{k}:".ljust(9)}#{v}" }
    puts '-' * 70
  end
end

namespace :imap do # rubocop:disable Metrics/BlockLength -- two task bodies in one namespace
  desc 'Dry run: classifica uma amostra do que imap:import faria, sem escrever nada'
  task scan: :environment do
    inbox = ImapImportOptions.inbox!
    sample = (ENV['SAMPLE'] || 400).to_i
    pacer = ImapImportOptions.pacer
    run = Import::Email::Backfill.new(inbox: inbox, kinds: [], pacer: pacer,
                                      folders: ImapImportOptions.folders, terms: ImapImportOptions.terms)
    imap = run.connect
    ImapImportOptions.header(inbox, Pastas: run.folders(imap).join(', '), Amostra: "#{sample} por pasta",
                                    Teto: "#{pacer.budget_mb_left}MB")

    totals = Hash.new(0)
    run.folders(imap).each do |folder|
      imap.examine(folder)
      uids = imap.uid_search(ImapImportOptions.terms)
      puts "\n#{folder}: #{uids.length} mensagens"
      next if uids.empty?

      kinds = ImapImportOptions.sample_kinds(imap, run, uids, sample, pacer)
      seen = kinds.values.sum
      kinds.sort_by { |_, v| -v }.each do |kind, count|
        projected = (uids.length * count / seen.to_f).round
        totals[kind] += projected
        puts "   #{kind.to_s.ljust(10)} #{count}/#{seen} (#{(100.0 * count / seen).round(1)}%)  -> ~#{projected}"
      end
    end
    run.close(imap)

    puts "\n#{'=' * 70}\nPROJECAO GERAL"
    totals.sort_by { |_, v| -v }.each { |kind, count| puts "  #{kind.to_s.ljust(12)} ~#{count}" }
  end

  desc 'Importa historico de e-mails do IMAP para uma inbox do Chatwoot'
  task import: :environment do
    inbox = ImapImportOptions.inbox!
    pacer = ImapImportOptions.pacer
    started = Time.zone.now
    attachments = ImapImportOptions.attachments

    ImapImportOptions.header(
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
    run.cursor.reset if ENV['RESET_CURSOR'].present?
    puts "Retoma:  #{run.cursor}"
    puts '-' * 70

    run.perform(&ImapImportOptions.printer(pacer, started))
    ImapImportOptions.report(run, pacer, started)
  end
end
