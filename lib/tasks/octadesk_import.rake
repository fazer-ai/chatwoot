# frozen_string_literal: true

# Imports an OctaDesk ticket export into an email inbox.
#
# The export is the ticketing system's own model: hundreds of thousands of tickets,
# already threaded and already attributed. It is a better source than the mailbox for
# everything it covers, and `imap:import` is left to the months that precede it.
#
#   INBOX_ID=1 ZIP=/path/ticket.zip LIMIT=200 bundle exec rails octadesk:import
#   INBOX_ID=1 ZIP=/path/ticket.zip ATTACHMENTS=1 bundle exec rails octadesk:import
#
#   INBOX_ID          required
#   ZIP               required, the *_ticket_ticket_*.zip
#   ATTACHMENTS       1 to also mirror the attachments off the vendor bucket
#   LIMIT             stop after this many newly imported tickets, so running again
#                     continues rather than re-reading the same ones
#   FROM_PART         resume from a part name, e.g. part_0007.json
#   MAX_LOAD          pause while the host's 1-minute load is above this (default 2.5)
#   FORM_ADDRESS      address the company's website form posts as, so the customer's own
#                     address is taken out of the ticket body instead
#   FORM_SENDER_NAME  display name that form posts under, same reason
module OctadeskImportOptions
  module_function

  # Cast rather than `present?`: mirroring is hundreds of gigabytes, and `ATTACHMENTS=0`
  # reads as "off" to whoever typed it and as "on" to a presence check.
  def attachments? = ActiveModel::Type::Boolean.new.cast(ENV.fetch('ATTACHMENTS', nil)).present?

  # Strict for the same reason the IMAP task is: `to_i` turns a typo into zero, and a zero
  # `LIMIT` stops at the first ticket while looking like a finished run.
  def limit
    raw = ENV['LIMIT'].presence
    return if raw.nil?

    value = Integer(raw, exception: false)
    abort "ERRO: LIMIT deve ser um inteiro positivo, veio #{raw.inspect}" if value.nil? || !value.positive?

    value
  end

  def printer(pacer, started)
    lambda do |event, payload|
      case event
      when :part then puts "\n#{payload[:part]}"
      when :paused then print "\r  [pausa] load #{payload[:load]} acima do teto...            "
      when :error then warn "\n  [ERRO] ticket #{payload[:ticket]}: #{payload[:error].class} #{payload[:error].message}"
      when :ticket then progress(payload[:stats], pacer, started)
      end
    end
  end

  # Printed every twenty-fifth ticket: the write is fast enough that one line per record
  # would spend real time on terminal output over half a million of them.
  def progress(stats, pacer, started)
    return unless (stats[:lidos] % 25).zero?

    print "\r  #{stats[:lidos]} lidos | #{stats[:tickets]} conversas | " \
          "#{stats[:mensagens]}+#{stats[:respostas]} msgs | #{stats[:anexos]} anexos | " \
          "load #{pacer.load_average} | #{ImapImportOptions.duration(Time.zone.now - started)}   "
  end

  def report(run, pacer, started)
    puts "\n#{'=' * 70}"
    puts run.stopped_by == :limite ? 'Parou no LIMIT. Rode de novo para continuar.' : 'Export esgotado.'
    run.stats.sort.each { |key, value| puts "  #{key.to_s.ljust(20)} #{value}" }
    puts "  #{'tempo'.ljust(20)} #{ImapImportOptions.duration(Time.zone.now - started)} " \
         "(pausado #{ImapImportOptions.duration(pacer.paused_for)})"
  end
end

namespace :octadesk do
  desc 'Importa o export de tickets do OctaDesk para uma inbox de e-mail'
  task import: :environment do
    inbox = Inbox.find_by(id: ENV.fetch('INBOX_ID', nil))
    abort 'ERRO: defina INBOX_ID' if inbox.nil?
    zip = ENV.fetch('ZIP', nil)
    abort 'ERRO: defina ZIP com o caminho do *_ticket_ticket_*.zip' if zip.blank? || !File.exist?(zip)

    pacer = Import::Email::Pacer.new(budget_mb: Float::INFINITY, max_load: ENV['MAX_LOAD'] || 2.5)
    started = Time.zone.now
    run = Import::Octadesk::Backfill.new(
      inbox: inbox, zip_path: zip, pacer: pacer,
      attachments: OctadeskImportOptions.attachments?, limit: OctadeskImportOptions.limit,
      from_part: ENV['FROM_PART'].presence,
      form_address: ENV['FORM_ADDRESS'].presence, form_sender_name: ENV['FORM_SENDER_NAME'].presence
    )

    puts "Inbox:   #{inbox.name} (##{inbox.id})  #{inbox.channel.email}"
    puts "Export:  #{File.basename(zip)}  (#{run.parts.size} partes)"
    puts "Anexos:  #{OctadeskImportOptions.attachments? ? 'sim, espelhando para o S3' : 'nao'}"
    puts '-' * 70

    run.perform(&OctadeskImportOptions.printer(pacer, started))
    OctadeskImportOptions.report(run, pacer, started)
  end
end
