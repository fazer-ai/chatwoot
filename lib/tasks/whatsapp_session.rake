# rubocop:disable Metrics/BlockLength
namespace :whatsapp do
  namespace :contract do
    desc 'Print the checksum of the vendored WhatsApp session contract'
    task checksum: :environment do
      puts Whatsapp::SessionContract.checksum
    end

    desc 'Fail when the vendored contract no longer matches CONTRACT_REF (used by CI)'
    task verify: :environment do
      reference = Whatsapp::SessionContract.reference
      actual = Whatsapp::SessionContract.checksum

      if reference['checksum'] == actual
        puts "contract ok (#{reference['repo']}@#{reference['ref'][0, 12]}, protocol v#{Whatsapp::SessionContract.protocol_version})"
      else
        warn "contract drift: CONTRACT_REF says #{reference['checksum']}, files hash to #{actual}"
        warn 'Run `rails whatsapp:contract:sync[<ref>]` to re-vendor, or revert the local edit.'
        exit 1
      end
    end

    desc 'Re-vendor the contract from a whatsapp-connector checkout (WHATSAPP_CONNECTOR_PATH)'
    task :sync, [:ref] => :environment do |_task, args|
      source = Pathname.new(ENV.fetch('WHATSAPP_CONNECTOR_PATH', Rails.root.join('../../whatsapp-connector').to_s)).expand_path
      raise "no contract at #{source}/contract" unless source.join('contract').directory?

      ref = args[:ref].presence || `git -C #{source} rev-parse HEAD`.strip
      target = Whatsapp::SessionContract.root
      FileUtils.rm_rf(target)
      FileUtils.mkdir_p(target)
      FileUtils.cp_r("#{source}/contract/.", target)
      FileUtils.rm_f(target.join('README.md'))
      Whatsapp::SessionContract.write_reference(repo: 'fazer-ai/whatsapp-connector', ref: ref)
      puts "vendored #{ref[0, 12]} (checksum #{Whatsapp::SessionContract.checksum})"
    end
  end

  # The consumer normally rides inside Sidekiq, which is the process that is already
  # there and already quiesced before a deploy. This is the WHATSAPP_CONNECTOR_CONSUMER=
  # standalone escape hatch: an installation that runs its Sidekiq somewhere the
  # connector's Redis is not, or that wants the event thread's failures on their own pager.
  desc 'Run the WhatsApp connector event consumer in the foreground'
  task consumer: :environment do
    # Consumer.enabled?, not Connector.enabled?: WHATSAPP_CONNECTOR_CONSUMER=off means
    # this installation does not read the streams at all, and a dedicated process that
    # started anyway would read them with no database pool reserved for its threads.
    abort 'the WhatsApp connector consumer is not enabled here; nothing to consume.' unless Whatsapp::Connector::Consumer.enabled?

    supervisor = Whatsapp::Connector::Consumer::Supervisor.new
    stopping = Queue.new
    # Trap context allows very little, so it only wakes the main thread up: releasing the
    # shards talks to Redis, which a handler must not do.
    %w[INT TERM].each { |signal| Signal.trap(signal) { stopping << signal } }

    supervisor.start
    Rails.logger.info("[WHATSAPP CONNECTOR] standalone consumer #{supervisor.consumer_id} started")
    stopping.pop
    supervisor.stop
    Rails.logger.info('[WHATSAPP CONNECTOR] standalone consumer stopped')
  end

  namespace :providers do
    desc 'Report WhatsApp inboxes grouped by provider and connection state'
    task report: :environment do
      rows = Channel::Whatsapp.group(:provider).count.sort_by { |_provider, count| -count }
      puts 'provider          inboxes  connections'
      rows.each do |provider, count|
        states = Channel::Whatsapp.where(provider: provider)
                                  .group("provider_connection->>'connection'").count
                                  .transform_keys { |state| state || 'n/a' }
                                  .map { |state, total| "#{state}=#{total}" }.join(' ')
        descriptor = Whatsapp::Session::Registry.descriptor(provider)
        legacy = descriptor&.legacy ? '  [legacy]' : ''
        puts format('%<provider>-16s %<count>8d  %<states>s%<legacy>s',
                    provider: provider, count: count, states: states, legacy: legacy)
      end
    end

    # Converting forces a re-pairing: the old session is terminated and nobody can be
    # messaged until someone scans a new QR. Run for real only with APPLY=1, so a
    # mistyped switch prints a plan instead of disconnecting a fleet. `DRY_RUN=0` is
    # deliberately not the way in: an env var whose absence is dangerous is the wrong
    # default for this.
    desc 'Convert one inbox to another provider (PROVIDER_CONFIG=json, APPLY=1 to execute)'
    task :convert, [:inbox_id, :target] => :environment do |_task, args|
      if args[:inbox_id].blank? || args[:target].blank?
        abort 'usage: rake "whatsapp:providers:convert[<inbox_id>,<target>]" PROVIDER_CONFIG=\'{...}\''
      end

      channel = WhatsappProviderConversion.channel_for(args[:inbox_id])
      begin
        config = WhatsappProviderConversion.parse_config(ENV.fetch('PROVIDER_CONFIG', nil))
      rescue ArgumentError => e
        abort e.message
      end
      WhatsappProviderConversion.announce_mode
      # Exits non-zero on failure, like the batch: a migration driven from a script reads
      # the status, and a silent success there is a conversion nobody notices did not run.
      abort 'conversion failed' unless WhatsappProviderConversion.convert(channel, args[:target], config)
    end

    # The config travels in the CSV rather than in the environment because a batch is
    # rows with different credentials. Columns: inbox_id,target,provider_config, where
    # provider_config is a JSON object; CSV quoting is what keeps its commas out of the
    # column split, which is also why this is not a rake argument list.
    desc 'Convert many inboxes from a CSV of inbox_id,target,provider_config (APPLY=1 to execute)'
    task :convert_batch, [:csv_path] => :environment do |_task, args|
      abort 'usage: rake "whatsapp:providers:convert_batch[path/to/plan.csv]"' if args[:csv_path].blank?
      abort "#{args[:csv_path]} does not exist" unless File.exist?(args[:csv_path])

      # The whole plan is parsed before the first inbox is touched. A malformed config on
      # row 40 used to surface only once rows 1 to 39 had already been converted, leaving a
      # half-migrated fleet and no summary; a plan that cannot be read is a file to fix,
      # not a batch to start.
      rows = CSV.read(args[:csv_path], headers: true)
      configs = rows.each_with_index.map do |row, index|
        WhatsappProviderConversion.parse_config(row['provider_config'])
      rescue ArgumentError => e
        abort "row #{index + 1}: #{e.message} (nothing was converted)"
      end

      WhatsappProviderConversion.announce_mode
      failures = rows.zip(configs).count do |row, config|
        channel = WhatsappProviderConversion.channel_for(row['inbox_id'], abort_on_missing: false)
        next true if channel.nil?

        !WhatsappProviderConversion.convert(channel, row['target'], config)
      end

      puts format('%<total>d row(s), %<failed>d failed', total: rows.size, failed: failures)
      abort 'batch finished with failures' if failures.positive?
    end

    namespace :legacy do
      desc 'List the inboxes still on a frozen provider, with what a conversion would cost'
      task report: :environment do
        legacy = Whatsapp::Session::Registry.descriptors.select(&:legacy?).map(&:key)
        channels = Channel::Whatsapp.where(provider: legacy).includes(inbox: :account)
        if channels.empty?
          puts "no inbox left on #{legacy.join(', ')}"
          next
        end

        puts 'account  inbox  provider  connection  phone            name'
        channels.find_each do |channel|
          inbox = channel.inbox
          puts format('%<account>7d  %<inbox>5d  %<provider>-8s  %<state>-10s  %<phone>-15s  %<name>s',
                      account: inbox.account_id, inbox: inbox.id, provider: channel.provider,
                      state: channel.provider_connection&.dig('connection') || 'n/a',
                      phone: channel.phone_number, name: inbox.name)
        end
        puts
        puts format('%<count>d inbox(es) on a frozen provider; each conversion needs a new pairing.', count: channels.size)
      end
    end

    namespace :session do
      # After a conversion the new provider knows nothing about the groups the old one
      # had synced, and a group thread with a stale member list is one where mentions and
      # admin actions silently address the wrong people.
      desc 'Re-sync every group of one session inbox (INTERVAL_SECONDS spaces the jobs)'
      task :resync_groups, [:inbox_id] => :environment do |_task, args|
        abort 'usage: rake "whatsapp:providers:session:resync_groups[<inbox_id>]"' if args[:inbox_id].blank?

        channel = WhatsappProviderConversion.channel_for(args[:inbox_id])
        # The capability, not the family: `zapi` pairs with a phone and so is session
        # family, but it declares no `groups` and its frozen service has no `sync_group`,
        # so every job this enqueued for one would die on NoMethodError. Reading the
        # capability also honours the instance-wide groups kill switch for free.
        unless Whatsapp::Session::Registry.capabilities_for(channel).include?('groups')
          abort "inbox #{args[:inbox_id]} is on #{channel.provider}, which cannot answer for groups"
        end

        inbox = channel.inbox
        contacts = Contact.where(account_id: inbox.account_id, group_type: :group)
                          .joins(:contact_inboxes).where(contact_inboxes: { inbox_id: inbox.id }).distinct
        interval = ENV.fetch('INTERVAL_SECONDS', '2').to_i.seconds
        WhatsappProviderConversion.announce_mode

        contacts.each_with_index do |contact, index|
          puts format('  %<id>7d  %<name>s', id: contact.id, name: contact.name)
          next unless WhatsappProviderConversion.apply?

          Contacts::SyncGroupJob.set(wait: interval * index).perform_later(contact, force: true, channel: channel)
        end

        tail = WhatsappProviderConversion.apply? ? ", spread over #{(interval * contacts.size).inspect}" : ''
        puts format('%<count>d group(s)%<tail>s', count: contacts.size, tail: tail)
      end
    end
  end
end
# rubocop:enable Metrics/BlockLength

# Shared by the conversion tasks above. A module rather than helpers in the rake block so
# the dry-run switch is read in exactly one place: a task that decided for itself whether
# it was applying is how half a batch runs for real.
module WhatsappProviderConversion
  # Only the session layer is a destination here, which is also what the dashboard's
  # convert picker offers. It is not a taste question: validating a target runs that
  # provider's `validate_provider_config?`, and every legacy and cloud one does it over
  # the network. 360dialog's goes further and POSTs a new webhook URL, so a dry run aimed
  # at it would rewrite a live inbox's delivery address while promising to change nothing.
  # A session backend's `validate_config` is shape-only by contract, which is what makes
  # the dry run below actually free of side effects.
  class << self
    # A method, not a constant. Rake evaluates a module body while it loads the task files,
    # which happens before the `:environment` prerequisite sets up autoloading, so naming an
    # app constant out here breaks *every* rake invocation with a NameError, `rake -T` and
    # `db:migrate` included. The spec suite cannot see it: `rails_helper` requires
    # `config/environment` before it calls `load_tasks`, so by then the constant resolves.
    # CI does catch it, but only as all 16 backend shards failing at `rake db:create` during
    # setup, which is a slow and opaque way to learn about a one-line mistake.
    def target_refused
      "target must be one of #{Whatsapp::Session::PROVIDERS.join(', ')} " \
        '(converting to a cloud or frozen provider contacts it, and is a one-inbox job for the dashboard)'
    end

    def apply?
      ENV.fetch('APPLY', nil) == '1'
    end

    def announce_mode
      puts apply? ? 'APPLY=1: converting for real' : 'dry run (pass APPLY=1 to execute)'
    end

    def channel_for(inbox_id, abort_on_missing: true)
      inbox = Inbox.find_by(id: inbox_id)
      channel = inbox&.channel
      return channel if channel.is_a?(Channel::Whatsapp)

      message = "inbox #{inbox_id} is not a WhatsApp inbox"
      abort_on_missing ? abort(message) : (puts("  SKIP  #{message}") || nil)
    end

    # Raises rather than aborts: the batch has rows after this one and has to decide for
    # itself, and a helper that kills the process takes that decision away from it.
    def parse_config(raw)
      return {} if raw.blank?

      parsed = JSON.parse(raw)
      raise ArgumentError, 'provider config must be a JSON object' unless parsed.is_a?(Hash)

      parsed
    rescue JSON::ParserError => e
      raise ArgumentError, "provider config is not valid JSON: #{e.message}"
    end

    # Validation runs the same way in both modes, so a dry run reports exactly what the
    # real one would refuse. `validate_config` is shape-only by contract, so nothing here
    # touches the provider until the conversion itself.
    def convert(channel, target, config)
      label = "inbox #{channel.inbox.id} (#{channel.provider} -> #{target})"
      return report(label, target_refused) unless Whatsapp::Session::PROVIDERS.include?(target.to_s)
      # Not a failure: it is the state the row asked for. Counting it as one meant a batch
      # rerun after a partial failure could never exit zero, since every row the first
      # attempt converted now lands here.
      return report(label, nil, verb: 'SKIP', note: 'already on that provider') if channel.provider == target.to_s

      invalid = validation_errors(channel, target, config)
      return report(label, invalid) if invalid

      return report(label, nil, verb: 'WOULD') unless apply?

      channel.convert_provider!(new_provider: target.to_s, new_provider_config: config)
      report(label, nil)
    # Deliberately everything, and only around one row. `convert_provider!` disconnects the
    # old session first, and Z-API's `disconnect_channel_provider` is an HTTParty call with
    # no timeout and no rescue of its own, so an unreachable host raises `Net::ReadTimeout`
    # or `SocketError` straight through. Letting that escape would kill the batch with
    # earlier rows already committed and no summary, which is the failure mode the plan
    # pre-parsing was added to prevent, arriving through a different door. The class name
    # goes in the message so a bug in here still reads as a bug.
    rescue StandardError => e
      report(label, "#{e.class}: #{e.message}")
    end

    private

    def validation_errors(channel, target, config)
      previous = [channel.provider, channel.provider_config.deep_dup]
      channel.assign_attributes(provider: target.to_s, provider_config: config)
      errors = channel.valid? ? nil : channel.errors.full_messages.join('; ')
      channel.assign_attributes(provider: previous.first, provider_config: previous.last)
      errors
    end

    def report(label, error, verb: 'OK', note: nil)
      return (puts "  FAIL  #{label}: #{error}") && false if error

      puts "  #{verb}    #{label}#{note ? ": #{note}" : ''}"
      true
    end
  end
end
