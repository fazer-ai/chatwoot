require 'spec_helper'
require 'fileutils'
require 'open3'
require 'tmpdir'

# The entrypoint decides, from argv alone, whether a container is a worker that has to wait
# for the schema. Getting that wrong in either direction is expensive and silent: a worker
# that is not recognised boots against a stale schema and drops records, and a console or a
# web server that IS recognised blocks on migrations that the web container is the one
# supposed to run.
#
# Run against a stub gate rather than the real one, in a temporary directory shaped like the
# app: the real sidekiq.sh waits on postgres, and what is under test here is the dispatch,
# not the wait.
# rubocop:disable RSpec/DescribeClass -- the subject is a shell script, not a constant
RSpec.describe 'docker/entrypoints/docker-entrypoint.sh', type: :script do
  let(:app_dir) { Dir.mktmpdir }

  before do
    FileUtils.mkdir_p(File.join(app_dir, 'docker/entrypoints'))

    entrypoint = File.join(app_dir, 'docker/entrypoints/docker-entrypoint.sh')
    FileUtils.cp(File.expand_path('../../docker/entrypoints/docker-entrypoint.sh', __dir__), entrypoint)
    FileUtils.chmod(0o755, entrypoint)

    gate = File.join(app_dir, 'docker/entrypoints/sidekiq.sh')
    File.write(gate, %(#!/bin/sh\necho "GATED: $*"\n))
    FileUtils.chmod(0o755, gate)
  end

  after { FileUtils.remove_entry(app_dir) }

  def run(*argv)
    Open3.capture3('docker/entrypoints/docker-entrypoint.sh', *argv, chdir: app_dir)
  end

  describe 'a worker' do
    it 'sends the ordinary sidekiq command through the gate' do
      out, _err, status = run('bundle', 'exec', 'sidekiq', '-C', 'config/sidekiq.yml')

      expect(status).to be_success
      expect(out).to eq("GATED: bundle exec sidekiq -C config/sidekiq.yml\n")
    end

    it 'sends a sidekiq command wrapped in sh -c through the gate' do
      out, _err, status = run('sh', '-c', 'bundle exec sidekiq -C config/sidekiq.yml')

      expect(status).to be_success
      expect(out).to eq("GATED: sh -c bundle exec sidekiq -C config/sidekiq.yml\n")
    end

    it 'passes the command on unchanged, so the gate can exec what was asked for' do
      out, _err, _status = run('bundle', 'exec', 'sidekiq')

      expect(out).to eq("GATED: bundle exec sidekiq\n")
    end
  end

  describe 'everything else' do
    it 'execs the web server without waiting' do
      out, _err, status = run('echo', 'rails', 's')

      expect(status).to be_success
      expect(out).to eq("rails s\n")
    end

    it 'does not mistake a runner script that merely mentions Sidekiq for a worker' do
      out, _err, status = run('echo', 'rails', 'runner', 'Sidekiq::Queue.new.size')

      expect(status).to be_success
      expect(out).to eq("rails runner Sidekiq::Queue.new.size\n")
    end

    # The discriminating case for how narrow the match has to be: a broad `*sidekiq*` glob
    # would gate this, and gating a one-shot command that is not a worker hangs it against a
    # database nobody is migrating.
    it 'does not mistake a path that merely contains sidekiq for a worker' do
      out, _err, status = run('echo', 'bundle', 'exec', 'rails', 'runner', 'config/initializers/sidekiq.rb')

      expect(status).to be_success
      expect(out).to eq("bundle exec rails runner config/initializers/sidekiq.rb\n")
    end

    it 'does not gate a non-worker command wrapped in sh -c' do
      out, _err, status = run('sh', '-c', 'echo rails s')

      expect(status).to be_success
      expect(out).to eq("rails s\n")
    end

    it 'refuses an empty command instead of exiting quietly as a container that did nothing' do
      _out, err, status = run

      expect(status).not_to be_success
      expect(err).to include('no command given')
    end
  end
end
# rubocop:enable RSpec/DescribeClass
