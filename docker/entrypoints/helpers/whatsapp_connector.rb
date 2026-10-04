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
# PostgreSQL server, created on the first start, a media directory local to the container
# (a cache, and one a second replica must not share: each connector sweeps the temporary
# files it does not know of), and a media token generated per container start, which Chatwoot reads from the connector's
# registry entry in Redis. Any WAC_* variable set explicitly wins over the derived value.
#
# Plain Ruby and the standard library only: this runs before, and outside of, bundler.

require 'fileutils'
require 'open3'
require 'securerandom'
require 'tmpdir'
require 'uri'

module WhatsappConnectorEmbedded # rubocop:disable Metrics/ModuleLength -- one self-contained file run before bundler; the length is the Rails-compatible URL handling
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

  # The connection options that mean the same to libpq (Rails, psql) and to lib/pq (the
  # connector), each with the variable psql reads it from. Anything else a DATABASE_URL may
  # carry is Rails' own (pool, checkout_timeout, ...), and lib/pq would send it to the server
  # as a startup parameter, which the server refuses.
  CONNECTION_OPTIONS = {
    'sslmode' => 'PGSSLMODE',
    'sslcert' => 'PGSSLCERT',
    'sslkey' => 'PGSSLKEY',
    'sslrootcert' => 'PGSSLROOTCERT',
    'connect_timeout' => 'PGCONNECT_TIMEOUT'
  }.freeze

  # Chatwoot's own connection, as Rails resolves it: what DATABASE_URL says, over the
  # POSTGRES_* parameters, over database.yml's defaults. Rails merges the URL into the
  # config field by field, so a URL without a password still takes POSTGRES_PASSWORD.
  def chatwoot_database(env)
    defaults = DATABASE_DEFAULTS.fetch(env.fetch('RAILS_ENV', 'production'), DATABASE_DEFAULTS['production'])
    config = {
      host: present(env['POSTGRES_HOST']) || 'localhost',
      port: present(env['POSTGRES_PORT']) || '5432',
      user: env.fetch('POSTGRES_USERNAME', defaults['username']),
      password: env.fetch('POSTGRES_PASSWORD', defaults['password']),
      database: env.fetch('POSTGRES_DATABASE', defaults['database']),
      options: {}
    }
    url = env['DATABASE_URL'].to_s
    url.empty? ? config : config.merge(database_from_url(url))
  end

  # Only the fields the URL actually carries, so the rest fall through to the defaults. A
  # field may also come as a query parameter, which wins over the URL's own parts, as it
  # does in Rails' resolver (under Rails' name or libpq's).
  def database_from_url(url)
    uri = URI(url)
    query = query_params(uri.query.to_s)
    url_fields(uri).merge(query_fields(query)).merge(options: query.slice(*CONNECTION_OPTIONS.keys))
  end

  # Percent-decoded and nothing more, as Rails' resolver reads it: a form decoder would turn
  # a literal plus into a space, and a password with one would connect Rails and not this.
  def query_params(query)
    query.split('&').to_h { |pair| pair.split('=', 2) }.transform_values { |value| URI::RFC2396_PARSER.unescape(value.to_s) }
  end

  def url_fields(uri)
    path = uri.path.to_s.delete_prefix('/')
    {
      host: present(uri.hostname),
      port: uri.port&.to_s,
      user: uri.user && URI.decode_uri_component(uri.user),
      password: uri.password && URI.decode_uri_component(uri.password),
      database: path.empty? ? nil : URI.decode_uri_component(path)
    }.compact
  end

  def query_fields(query)
    {
      host: present(query['host']),
      port: present(query['port']),
      user: query['username'] || query['user'],
      password: query['password'],
      database: present(query['database']) || present(query['dbname'])
    }.compact
  end

  def connector_database_name(env)
    "#{chatwoot_database(env)[:database]}#{DATABASE_SUFFIX}"
  end

  # lib/pq, the connector's driver, defaults to sslmode=require where libpq (what Rails
  # uses) defaults to prefer. Left unset, a server without TLS that Chatwoot reaches fine
  # would refuse the connector, so the URL says prefer unless the operator said otherwise.
  def connector_database_url(env)
    db = chatwoot_database(env)
    options = { 'sslmode' => present(env['PGSSLMODE']) || 'prefer' }.merge(db[:options])

    userinfo = [db[:user], db[:password]].compact.map { |part| URI.encode_uri_component(part) }.join(':')
    host = db[:host].include?(':') ? "[#{db[:host]}]" : db[:host]
    "postgres://#{userinfo}#{'@' unless userinfo.empty?}#{host}:#{db[:port]}/" \
      "#{URI.encode_uri_component(connector_database_name(env))}?#{URI.encode_www_form(options)}"
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

  # `on_spawn` gets psql's pid, so whoever runs it can end it: psql has no timeout of its own,
  # and a server that stopped answering would otherwise hold it, and its caller, forever.
  def psql(env, sql, on_spawn: nil)
    db = chatwoot_database(env)
    Open3.popen3(psql_env(db), 'psql', '-X', '-q', '-t', '-A', '-v', 'ON_ERROR_STOP=1',
                 '-h', db[:host], '-p', db[:port], '-U', db[:user].to_s, '-d', db[:database], '-c', sql) do |stdin, out, err, wait|
      stdin.close
      on_spawn&.call(wait.pid)
      error = Thread.new { err.read }
      [out.read, error.value, wait.value]
    end
  end

  # The URL's connection options reach psql the way libpq reads them from the environment;
  # the ones set as PG* variables on the container are inherited as they are.
  def psql_env(db)
    db[:options].each_with_object({ 'PGPASSWORD' => db[:password].to_s }) do |(option, value), pg_env|
      pg_env[CONNECTION_OPTIONS.fetch(option)] = value
    end
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
                   media_root: File.join(Dir.tmpdir, 'whatsapp-connector'))
      @command = command
      @env = env
      @binary = binary
      @media_root = present_or(env['WAC_MEDIA_ROOT'], media_root)
      # One token per container start rather than per connector start: a connector that
      # restarts keeps answering the token Chatwoot already read.
      @media_token = present_or(env['WAC_MEDIA_TOKEN'], SecureRandom.hex(32))
      @stopping = false
      @connector_pid = nil
      @bootstrap_pid = nil
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
          kill(signal, @bootstrap_pid)
          wake
        end
      end
      # Sidekiq's own operational signals (TSTP quiets it, TTIN dumps its threads) reach this
      # process now, since it is PID 1. They are the worker's alone.
      %w[TSTP TTIN].each do |signal|
        Signal.trap(signal) { kill(signal, @sidekiq_pid) }
      end
    end

    def stop_connector
      @stopping = true
      kill('TERM', @connector_pid)
      kill('TERM', @bootstrap_pid)
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
      unless WhatsappConnectorEmbedded.present(@env['WAC_DATABASE_URL'])
        WhatsappConnectorEmbedded.ensure_database(@env, runner: method(:bootstrap_psql))
      end
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

    # Tracked like the connector, so a worker that exits while the database is not answering
    # still takes the container down instead of waiting on psql.
    def bootstrap_psql(env, sql)
      WhatsappConnectorEmbedded.psql(env, sql, on_spawn: lambda { |pid|
        @bootstrap_pid = pid
        # a stop that landed before the pid was known found nothing to signal
        kill('TERM', pid) if @stopping
      })
    ensure
      @bootstrap_pid = nil
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
