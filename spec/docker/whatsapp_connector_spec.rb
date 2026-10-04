require 'spec_helper'
require 'fileutils'
require 'open3'
require 'timeout'
require 'tmpdir'
require_relative '../../docker/entrypoints/helpers/whatsapp_connector'

# The connector runs inside the Sidekiq container, and the order of who stops whom is the
# part that can lose something: a connector killed without SIGTERM keeps its session leases
# until they run out, and a worker taken down by a connector crash is a WhatsApp outage
# turned into a Chatwoot outage. The supervisor runs here against stub processes, which
# record what happened to them in files.
# rubocop:disable RSpec/DescribeClass -- the subject is the script, run as the image runs it
RSpec.describe 'docker/entrypoints/helpers/whatsapp_connector.rb', type: :script do
  let(:dir) { Dir.mktmpdir }
  let(:bin_dir) { File.join(dir, 'bin') }
  let(:script) { File.expand_path('../../docker/entrypoints/helpers/whatsapp_connector.rb', __dir__) }

  before do
    FileUtils.mkdir_p(bin_dir)
    # Records each start with the environment it got, and each SIGTERM; exits when told to
    # through a file, so a test can crash it on purpose.
    stub('whatsapp-connector', <<~SH)
      echo "start $$ $WAC_ENGINE $WAC_DATABASE_URL $WAC_MEDIA_ROOT $WAC_MEDIA_TOKEN" >> "#{dir}/connector"
      trap 'echo "term $$" >> "#{dir}/connector"; exit 0' TERM
      while [ ! -f "#{dir}/crash" ]; do sleep 0.05; done
      rm -f "#{dir}/crash"
      exit 3
    SH
    stub('worker', <<~SH)
      echo "start $$" >> "#{dir}/worker"
      # like Sidekiq, it takes its time to finish once told to stop
      trap 'echo "term $$" >> "#{dir}/worker"; echo 0 > "#{dir}/worker_exit.later"' TERM
      while [ ! -f "#{dir}/worker_exit" ]; do sleep 0.05; done
      exit "$(cat "#{dir}/worker_exit")"
    SH
    stub('psql', "echo 1\n")
  end

  after { FileUtils.remove_entry(dir) }

  def stub(name, body)
    path = File.join(bin_dir, name)
    File.write(path, "#!/bin/sh\n#{body}")
    FileUtils.chmod(0o755, path)
  end

  def start
    env = {
      'PATH' => "#{bin_dir}:#{ENV.fetch('PATH')}",
      'POSTGRES_HOST' => 'pg', 'POSTGRES_USERNAME' => 'cw', 'POSTGRES_PASSWORD' => 'pw',
      'POSTGRES_DATABASE' => 'chatwoot_production', 'WAC_MEDIA_ROOT' => File.join(dir, 'media')
    }
    stdin, out, wait = Open3.popen2e(env, 'ruby', script, 'worker')
    stdin.close
    @output = out
    wait
  end

  def lines(name)
    path = File.join(dir, name)
    File.exist?(path) ? File.readlines(path, chomp: true) : []
  end

  def stop(wait)
    return unless wait&.alive?

    Process.kill('TERM', wait.pid)
    File.write(File.join(dir, 'worker_exit'), '0')
    Timeout.timeout(10) { wait.value }
  end

  def eventually(timeout = 10)
    Timeout.timeout(timeout) do
      sleep 0.05 until yield
    end
  end

  it 'starts the worker and the connector, and the connector gets the derived environment' do
    wait = start
    eventually { lines('worker').any? && lines('connector').any? }

    _, pid, engine, url, media_root, token = lines('connector').first.split
    expect(pid).to match(/\A\d+\z/)
    expect(engine).to eq('whatsmeow')
    expect(url).to eq('postgres://cw:pw@pg:5432/chatwoot_production_whatsapp_connector?sslmode=prefer')
    expect(media_root).to eq(File.join(dir, 'media'))
    expect(token).to match(/\A\h{64}\z/)
    expect(Dir.exist?(File.join(dir, 'media'))).to be(true)
  ensure
    stop(wait)
  end

  it 'forwards SIGTERM to both and exits with the worker status' do
    wait = start
    eventually { lines('worker').any? && lines('connector').any? }

    Process.kill('TERM', wait.pid)
    # the connector hears it while the worker is still draining: waiting for the worker
    # first would spend the container's stop grace period before the leases go back
    eventually { lines('connector').grep(/\Aterm /).size == 1 && lines('worker').grep(/\Aterm /).size == 1 }
    expect(wait).to be_alive

    File.rename(File.join(dir, 'worker_exit.later'), File.join(dir, 'worker_exit'))
    status = Timeout.timeout(10) { wait.value }

    expect(status.exitstatus).to eq(0)
  end

  it 'starts a crashed connector again with the same token, without touching the worker' do
    wait = start
    eventually { lines('connector').any? }
    worker_before = lines('worker')

    FileUtils.touch(File.join(dir, 'crash'))
    eventually { lines('connector').grep(/\Astart /).size == 2 }

    first, second = lines('connector').grep(/\Astart /).map(&:split)
    expect(second[1]).not_to eq(first[1])
    expect(second[5]).to eq(first[5])
    expect(lines('worker')).to eq(worker_before)
    expect(wait).to be_alive
  ensure
    stop(wait)
  end

  it 'stops the connector and exits with the status of a worker that died on its own' do
    wait = start
    eventually { lines('worker').any? && lines('connector').any? }

    File.write(File.join(dir, 'worker_exit'), '7')
    status = Timeout.timeout(10) { wait.value }

    expect(status.exitstatus).to eq(7)
    expect(lines('connector').grep(/\Aterm /).size).to eq(1)
  end

  describe WhatsappConnectorEmbedded do
    let(:base) { { 'POSTGRES_HOST' => 'pg', 'POSTGRES_USERNAME' => 'cw', 'POSTGRES_PASSWORD' => 'p@ss:w', 'POSTGRES_DATABASE' => 'cw_db' } }

    def env_for(extra = {})
      described_class.connector_env(base.merge(extra), media_token: 'tok', media_root: '/m')
    end

    it 'derives the database from DATABASE_URL before the POSTGRES_* parameters, as Rails does' do
      url = env_for('DATABASE_URL' => 'postgres://u:secret@db.internal:6543/app?sslmode=require')['WAC_DATABASE_URL']

      expect(url).to eq('postgres://u:secret@db.internal:6543/app_whatsapp_connector?sslmode=require')
    end

    it 'escapes credentials and follows PGSSLMODE when the URL names no sslmode' do
      url = env_for('PGSSLMODE' => 'disable')['WAC_DATABASE_URL']

      expect(url).to eq('postgres://cw:p%40ss%3Aw@pg:5432/cw_db_whatsapp_connector?sslmode=disable')
    end

    it 'maps the Chatwoot names the connector knows by another name' do
      env = env_for('WHATSAPP_CONNECTOR_EVENT_SHARDS' => '8', 'WHATSAPP_CONNECTOR_REDIS_PREFIX' => 'x:')

      expect(env).to include('WAC_EVENT_SHARDS' => '8', 'WAC_REDIS_PREFIX' => 'x:', 'WAC_ENGINE' => 'whatsmeow',
                             'WAC_MEDIA_ROOT' => '/m', 'WAC_MEDIA_TOKEN' => 'tok')
    end

    it 'never overrides an explicit WAC_* value' do
      env = env_for('WAC_ENGINE' => 'fake', 'WAC_DATABASE_URL' => 'sqlite:x.db', 'WAC_EVENT_SHARDS' => '4',
                    'WHATSAPP_CONNECTOR_EVENT_SHARDS' => '8')

      expect(env.keys).not_to include('WAC_ENGINE', 'WAC_DATABASE_URL', 'WAC_EVENT_SHARDS')
    end

    describe '.ensure_database' do
      let(:calls) { [] }
      let(:ok) { instance_double(Process::Status, success?: true) }
      let(:failed) { instance_double(Process::Status, success?: false) }

      def runner(answers)
        lambda do |_env, sql|
          calls << sql
          answers.shift.call(sql)
        end
      end

      it 'creates the database when it is missing' do
        described_class.ensure_database(base, runner: runner([->(_) { ['', '', ok] }, ->(_) { ['', '', ok] }]))

        expect(calls).to eq(["SELECT 1 FROM pg_database WHERE datname = 'cw_db_whatsapp_connector'",
                             'CREATE DATABASE "cw_db_whatsapp_connector"'])
      end

      it 'leaves an existing database alone' do
        described_class.ensure_database(base, runner: runner([->(_) { ["1\n", '', ok] }]))

        expect(calls.size).to eq(1)
      end

      it 'accepts losing the race to another replica' do
        answers = [->(_) { ['', '', ok] }, ->(_) { ['', 'already exists', failed] }, ->(_) { ["1\n", '', ok] }]

        expect { described_class.ensure_database(base, runner: runner(answers)) }.not_to raise_error
      end

      it 'fails when the database cannot be created and does not exist' do
        answers = [->(_) { ['', '', ok] }, ->(_) { ['', 'permission denied to create database', failed] }, ->(_) { ['', '', ok] }]

        expect { described_class.ensure_database(base, runner: runner(answers)) }
          .to raise_error(/permission denied to create database/)
      end
    end
  end
end
# rubocop:enable RSpec/DescribeClass
