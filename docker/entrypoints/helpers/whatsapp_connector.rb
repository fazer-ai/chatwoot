#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs fazer-ai/whatsapp-connector next to Sidekiq, in the same container.
#
# The image carries the connector's binary (docker/Dockerfile copies it from the published
# image at a pinned version), and sidekiq.sh hands the worker's command to this file instead
# of exec'ing it whenever WHATSAPP_CONNECTOR_ENABLED=true and WHATSAPP_CONNECTOR_EMBEDDED is
# not false. From here on this process is PID 1 and the parent of both:
#
# - Sidekiq is the container. When it exits, for whatever reason, the connector is stopped
#   and this process exits with Sidekiq's status, so the restart policy and the healthcheck
#   see exactly what they saw before the connector was here.
# - The connector is not. When it exits it is started again, with a backoff, and Sidekiq is
#   never touched: a WhatsApp outage must not take the worker down with it.
# - SIGTERM and SIGINT go to both. The connector answers by handing its session leases back
#   to Redis, which is what lets another instance (or this one, restarted) pick the sessions
#   up at once instead of waiting for the leases to run out.
#
# Everything the connector needs is derived from what Chatwoot already has: the same Redis
# (it reads REDIS_URL and REDIS_PASSWORD itself), a database of its own on the same
# PostgreSQL server, created on the first start, a media directory under storage/, and a
# media token generated per container start, which Chatwoot reads from the connector's
# registry entry in Redis. Any WAC_* variable set explicitly wins over the derived value.
#
# Plain Ruby and the standard library only: this runs before, and outside of, bundler.

require 'fileutils'
require 'open3'
require 'securerandom'
require 'uri'

module WhatsappConnectorEmbedded
  DATABASE_SUFFIX = '_whatsapp_connector'
  MAX_BACKOFF = 30
  # A connector that stayed up this long is treated as healthy, and its next crash starts
  # the backoff over instead of continuing it.
  HEALTHY_AFTER = 60

  # The defaults config/database.yml falls back to, per environment, so that the connector's
  # database sits next to the one Rails actually connects to.
  DATABASE_DEFAULTS = {
    'production' => { 'database' => 'chatwoot_production', 'username' => 'chatwoot_prod', 'password' => 'chatwoot_prod' },
    'test' => { 'database' => 'chatwoot_test', 'username' => 'postgres', 'password' => '' },
    'development' => { 'database' => 'chatwoot_dev', 'username' => 'postgres', 'password' => '' }
  }.freeze

  module_function

  def log(message)
    warn "[whatsapp-connector] #{message}"
  end

  # Chatwoot's own connection, as Rails resolves it: DATABASE_URL wins over the POSTGRES_*
  # parameters, which fall back to database.yml's defaults.
  def chatwoot_database(env)
    url = env['DATABASE_URL'].to_s
    return database_from_url(url) unless url.empty?

    defaults = DATABASE_DEFAULTS.fetch(env.fetch('RAILS_ENV', 'production'), DATABASE_DEFAULTS['production'])
    {
      host: present(env['POSTGRES_HOST']) || 'localhost',
      port: present(env['POSTGRES_PORT']) || '5432',
      user: env.fetch('POSTGRES_USERNAME', defaults['username']),
      password: env.fetch('POSTGRES_PASSWORD', defaults['password']),
      database: env.fetch('POSTGRES_DATABASE', defaults['database']),
      query: nil
    }
  end

  def database_from_url(url)
    uri = URI(url)
    {
      host: uri.host || 'localhost',
      port: (uri.port || 5432).to_s,
      user: uri.user && URI.decode_www_form_component(uri.user),
      password: uri.password && URI.decode_www_form_component(uri.password),
      database: URI.decode_www_form_component(uri.path.delete_prefix('/')),
      query: uri.query
    }
  end

  def connector_database_name(env)
    "#{chatwoot_database(env)[:database]}#{DATABASE_SUFFIX}"
  end

  # lib/pq, the connector's driver, defaults to sslmode=require where libpq (what Rails
  # uses) defaults to prefer. Left unset, a server without TLS that Chatwoot reaches fine
  # would refuse the connector, so the URL says prefer unless the operator said otherwise.
  def connector_database_url(env)
    db = chatwoot_database(env)
    params = URI.decode_www_form(db[:query].to_s)
    params << ['sslmode', present(env['PGSSLMODE']) || 'prefer'] unless params.any? { |k, _| k == 'sslmode' }

    userinfo = [db[:user], db[:password]].compact.map { |part| URI.encode_www_form_component(part) }.join(':')
    host = db[:host].include?(':') ? "[#{db[:host]}]" : db[:host]
    "postgres://#{userinfo}#{'@' unless userinfo.empty?}#{host}:#{db[:port]}/" \
      "#{URI.encode_www_form_component(connector_database_name(env))}?#{URI.encode_www_form(params)}"
  end

  # Creates the connector's database when it does not exist yet. Two replicas starting
  # together both see it missing and both try; the loser's CREATE fails with "already
  # exists", so a failed CREATE is only an error when the database is still not there.
  def ensure_database(env, runner: method(:psql))
    name = connector_database_name(env)
    return if database_exists?(env, name, runner)

    _out, err, status = runner.call(env, "CREATE DATABASE #{quote_ident(name)}")
    return if status.success?
    return if database_exists?(env, name, runner)

    raise "could not create database #{name}: #{err.strip}"
  end

  def database_exists?(env, name, runner)
    out, err, status = runner.call(env, "SELECT 1 FROM pg_database WHERE datname = #{quote_literal(name)}")
    raise "could not list databases: #{err.strip}" unless status.success?

    out.strip == '1'
  end

  def psql(env, sql)
    db = chatwoot_database(env)
    pg_env = { 'PGPASSWORD' => db[:password].to_s }
    pg_env['PGSSLMODE'] = env['PGSSLMODE'] if present(env['PGSSLMODE'])
    Open3.capture3(pg_env, 'psql', '-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1',
                   '-h', db[:host], '-p', db[:port], '-U', db[:user].to_s, '-d', db[:database], '-c', sql)
  end

  def quote_ident(name)
    %("#{name.gsub('"', '""')}")
  end

  def quote_literal(value)
    "'#{value.gsub("'", "''")}'"
  end

  # The connector's environment: Chatwoot's, plus what the connector calls by another name
  # or cannot derive on its own. An explicit WAC_* value is never overwritten.
  def connector_env(env, media_token:, media_root:)
    derived = {
      'WAC_ENGINE' => 'whatsmeow',
      'WAC_MEDIA_ROOT' => media_root,
      'WAC_MEDIA_TOKEN' => media_token
    }
    derived['WAC_EVENT_SHARDS'] = env['WHATSAPP_CONNECTOR_EVENT_SHARDS'] if present(env['WHATSAPP_CONNECTOR_EVENT_SHARDS'])
    derived['WAC_REDIS_PREFIX'] = env['WHATSAPP_CONNECTOR_REDIS_PREFIX'] if present(env['WHATSAPP_CONNECTOR_REDIS_PREFIX'])
    derived['WAC_DATABASE_URL'] = connector_database_url(env) unless present(env['WAC_DATABASE_URL'])

    derived.reject { |key, _| present(env[key]) }
  end

  def present(value)
    value unless value.nil? || value.empty? # rubocop:disable Rails/Blank -- runs before bundler, without ActiveSupport
  end

  class Supervisor
    def initialize(command, env: ENV.to_h, binary: ENV.fetch('WHATSAPP_CONNECTOR_BIN', 'whatsapp-connector'),
                   media_root: File.expand_path('../../../storage/whatsapp-connector', __dir__))
      @command = command
      @env = env
      @binary = binary
      @media_root = present_or(env['WAC_MEDIA_ROOT'], media_root)
      # One token per container start rather than per connector start: a connector that
      # restarts keeps answering the token Chatwoot already read.
      @media_token = present_or(env['WAC_MEDIA_TOKEN'], SecureRandom.hex(32))
      @stopping = false
      @connector_pid = nil
      @wake_r, @wake_w = IO.pipe
    end

    def run
      trap_signals
      @sidekiq_pid = Process.spawn(*@command)
      connector = Thread.new { keep_connector_running }

      _, status = Process.wait2(@sidekiq_pid)
      log "worker exited (#{describe(status)}), stopping the connector" unless @stopping
      stop_connector
      connector.join
      exit_code(status)
    end

    private

    def trap_signals
      %w[TERM INT].each do |signal|
        Signal.trap(signal) do
          @stopping = true
          kill(signal, @sidekiq_pid)
          kill(signal, @connector_pid)
          wake
        end
      end
    end

    def stop_connector
      @stopping = true
      kill('TERM', @connector_pid)
      wake
    end

    def keep_connector_running
      backoff = 1
      until @stopping
        started = monotonic
        status = run_connector_once
        break if @stopping

        backoff = 1 if monotonic - started >= HEALTHY_AFTER
        log "connector #{status ? "exited (#{describe(status)})" : 'did not start'}, starting it again in #{backoff}s"
        pause(backoff)
        backoff = [backoff * 2, MAX_BACKOFF].min
      end
    end

    def run_connector_once
      WhatsappConnectorEmbedded.ensure_database(@env) unless WhatsappConnectorEmbedded.present(@env['WAC_DATABASE_URL'])
      FileUtils.mkdir_p(@media_root)
      env = WhatsappConnectorEmbedded.connector_env(@env, media_token: @media_token, media_root: @media_root)
      @connector_pid = Process.spawn(env, @binary, 'serve')
      # a signal that landed between the spawn and the assignment above found no pid to forward to
      kill('TERM', @connector_pid) if @stopping
      _, status = Process.wait2(@connector_pid)
      @connector_pid = nil
      status
    rescue StandardError => e
      log e.message
      nil
    end

    def pause(seconds)
      @wake_r.wait_readable(seconds)
    end

    def wake
      @wake_w.write_nonblock('.')
    rescue IO::WaitWritable
      nil
    end

    def kill(signal, pid)
      Process.kill(signal, pid) if pid
    rescue Errno::ESRCH
      nil
    end

    def exit_code(status)
      status.exitstatus || (128 + status.termsig)
    end

    def describe(status)
      status.exitstatus ? "status #{status.exitstatus}" : "signal #{status.termsig}"
    end

    def monotonic
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def present_or(value, fallback)
      WhatsappConnectorEmbedded.present(value) || fallback
    end

    def log(message)
      WhatsappConnectorEmbedded.log(message)
    end
  end
end

if $PROGRAM_NAME == __FILE__
  if ARGV.empty?
    WhatsappConnectorEmbedded.log 'no worker command given'
    exit 1
  end
  exit WhatsappConnectorEmbedded::Supervisor.new(ARGV).run
end
