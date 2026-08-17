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
  end
end
# rubocop:enable Metrics/BlockLength
