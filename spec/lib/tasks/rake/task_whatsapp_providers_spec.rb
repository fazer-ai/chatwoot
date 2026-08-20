require 'rake'
require 'rails_helper'

RSpec.describe Rake::Task do
  describe 'whatsapp:providers' do
    let(:account) { create(:account) }
    let(:channel) do
      create(:channel_whatsapp, account: account, provider: 'baileys',
                                validate_provider_config: false, sync_templates: false)
    end
    let(:uazapi_config) { { 'base_url' => 'https://free.uazapi.com', 'token' => 'tok' } }

    def run(name, *)
      task = Rake::Task[name]
      # Rake refuses a second invoke of the same task in one process, and these examples
      # share one.
      task.reenable
      task.invoke(*)
    end

    before do
      account.update!(whatsapp_uazapi_enabled: true)
      # The conversion terminates the old session before it swaps the provider, and the
      # frozen Baileys service does that over the network.
      allow_any_instance_of(Whatsapp::Providers::WhatsappBaileysService) # rubocop:disable RSpec/AnyInstance
        .to receive(:disconnect_channel_provider).and_return(true)
    end

    describe 'whatsapp:providers:convert' do
      # The whole point of the default: someone who forgets the switch gets a plan, not a
      # fleet of inboxes that need re-pairing.
      it 'changes nothing without APPLY' do
        with_modified_env APPLY: nil, PROVIDER_CONFIG: uazapi_config.to_json do
          expect { run('whatsapp:providers:convert', channel.inbox.id.to_s, 'uazapi') }
            .to output(/dry run.*WOULD/m).to_stdout
        end

        expect(channel.reload.provider).to eq('baileys')
      end

      it 'converts when told to' do
        with_modified_env APPLY: '1', PROVIDER_CONFIG: uazapi_config.to_json do
          expect { run('whatsapp:providers:convert', channel.inbox.id.to_s, 'uazapi') }
            .to output(/OK/).to_stdout
        end

        expect(channel.reload.provider).to eq('uazapi')
        expect(channel.provider_config).to include(uazapi_config)
      end

      # A dry run that reported success and a real run that then failed would be worse than
      # no dry run at all, so both modes validate the same way.
      it 'reports the config the conversion would refuse, in either mode' do
        with_modified_env APPLY: nil, PROVIDER_CONFIG: { 'base_url' => 'nope' }.to_json do
          expect { run('whatsapp:providers:convert', channel.inbox.id.to_s, 'uazapi') }
            .to output(/FAIL.*base_url/m).to_stdout
        end

        expect(channel.reload.provider).to eq('baileys')
      end

      it 'refuses a provider that does not exist' do
        with_modified_env APPLY: '1', PROVIDER_CONFIG: '{}' do
          expect { run('whatsapp:providers:convert', channel.inbox.id.to_s, 'carrier-pigeon') }
            .to output(/FAIL.*not a known provider/m).to_stdout
        end

        expect(channel.reload.provider).to eq('baileys')
      end

      it 'refuses a provider config that is not a JSON object' do
        with_modified_env APPLY: '1', PROVIDER_CONFIG: '[1,2]' do
          expect { run('whatsapp:providers:convert', channel.inbox.id.to_s, 'uazapi') }
            .to raise_error(SystemExit)
        end
      end
    end

    describe 'whatsapp:providers:convert_batch' do
      let(:other) do
        create(:channel_whatsapp, account: account, provider: 'baileys', phone_number: '+551188887777',
                                  validate_provider_config: false, sync_templates: false)
      end
      let(:csv_path) { Rails.root.join('tmp/whatsapp_convert_plan.csv').to_s }

      after { FileUtils.rm_f(csv_path) }

      def write_plan(rows)
        CSV.open(csv_path, 'w', write_headers: true, headers: %w[inbox_id target provider_config]) do |csv|
          rows.each { |row| csv << row }
        end
      end

      it 'converts every row it can and exits non-zero when one fails' do
        write_plan([
                     [channel.inbox.id, 'uazapi', uazapi_config.to_json],
                     [other.inbox.id, 'uazapi', { 'base_url' => 'nope' }.to_json]
                   ])

        with_modified_env APPLY: '1' do
          expect { run('whatsapp:providers:convert_batch', csv_path) }
            .to raise_error(SystemExit)
            .and output(/2 row\(s\), 1 failed/).to_stdout
        end

        expect(channel.reload.provider).to eq('uazapi')
        expect(other.reload.provider).to eq('baileys')
      end

      # An id that no longer resolves is a stale plan, not a reason to stop: the rows after
      # it are still inboxes someone is waiting to have converted.
      it 'skips a row whose inbox is gone and keeps going' do
        write_plan([
                     [0, 'uazapi', uazapi_config.to_json],
                     [channel.inbox.id, 'uazapi', uazapi_config.to_json]
                   ])

        with_modified_env APPLY: '1' do
          expect { run('whatsapp:providers:convert_batch', csv_path) }
            .to raise_error(SystemExit)
            .and output(/SKIP.*not a WhatsApp inbox/m).to_stdout
        end

        expect(channel.reload.provider).to eq('uazapi')
      end
    end

    describe 'whatsapp:providers:legacy:report' do
      it 'lists the inboxes still on a frozen provider' do
        channel

        expect { run('whatsapp:providers:legacy:report') }
          .to output(/#{channel.inbox.id}.*baileys.*1 inbox\(es\) on a frozen provider/m).to_stdout
      end

      it 'says so when there are none' do
        expect { run('whatsapp:providers:legacy:report') }.to output(/no inbox left on/).to_stdout
      end
    end

    describe 'whatsapp:providers:session:resync_groups' do
      let(:session_channel) do
        create(:channel_whatsapp, account: account, provider: 'uazapi', provider_config: uazapi_config,
                                  validate_provider_config: false, sync_templates: false)
      end
      let(:group) { create(:contact, account: account, group_type: :group, name: 'Time') }

      before do
        create(:contact_inbox, contact: group, inbox: session_channel.inbox)
      end

      it 'enqueues nothing without APPLY' do
        with_modified_env APPLY: nil do
          expect { run('whatsapp:providers:session:resync_groups', session_channel.inbox.id.to_s) }
            .to output(/dry run.*Time/m).to_stdout
        end

        expect(Contacts::SyncGroupJob).to have_been_enqueued.exactly(0).times
      end

      it 'enqueues one forced sync per group when told to' do
        with_modified_env APPLY: '1' do
          expect { run('whatsapp:providers:session:resync_groups', session_channel.inbox.id.to_s) }
            .to output(/1 group\(s\), spread over/).to_stdout
        end

        expect(Contacts::SyncGroupJob).to have_been_enqueued.with(group, force: true, channel: session_channel)
      end

      # Groups belong to the session family; asking a cloud inbox for them is a mistake
      # worth naming rather than an empty run that looks like success.
      it 'refuses an inbox whose provider has no groups' do
        cloud = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud',
                                          validate_provider_config: false, sync_templates: false)

        expect { run('whatsapp:providers:session:resync_groups', cloud.inbox.id.to_s) }
          .to raise_error(SystemExit)
      end
    end
  end
end
