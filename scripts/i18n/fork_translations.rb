#!/usr/bin/env ruby
# frozen_string_literal: true

# Guards the boundary between upstream's translations and the fork's.
#
#   ruby scripts/i18n/fork_translations.rb check
#   ruby scripts/i18n/fork_translations.rb drift [--base vX.Y.Z]
#   ruby scripts/i18n/fork_translations.rb scaffold es
#
# `check` needs nothing but the working tree. `drift` needs the upstream tag to
# be fetched first, which the CI workflow does explicitly since the fork's
# remote does not carry Chatwoot's tags.

require 'json'
require 'yaml'
require 'open3'
require 'fileutils'

FE_UPSTREAM = 'app/javascript/dashboard/i18n/locale'
FE_FORK = 'app/javascript/dashboard/i18n/fazer-ai/locale'
BE_FORK_GLOB = 'config/locales/fazer_ai*.yml'
OVERRIDES = 'overrides.json'
REFERENCE_LOCALE = 'en'

# The Chatwoot release whose translations this fork currently carries.
# The sync-fork flow bumps it together with the upstream merge.
UPSTREAM_BASE = 'v4.16.2'

class ForkTranslations
  def initialize
    @errors = []
  end

  def check
    check_reference_locale_exists
    check_fork_keys_are_not_duplicated_upstream
    check_every_key_exists_in_reference
    check_upstream_indexes_ignore_the_fork
    report_coverage
    finish
  end

  # Every upstream translation file must still match the tracked release.
  def drift(base)
    unless system("git rev-parse --verify --quiet #{base}^{commit} > /dev/null")
      abort "tag #{base} nao esta disponivel neste clone (git fetch --tags)"
    end

    changed = capture('git', 'diff', '--name-only', base, '--', FE_UPSTREAM, 'config/locales')
              .split("\n")
              .reject { |path| File.fnmatch(BE_FORK_GLOB, path) }

    changed.each do |path|
      @errors << "#{path} diverge de #{base}: traducoes do fork vao em #{FE_FORK}/<locale>/ ou config/locales/fazer_ai.<locale>.yml"
    end
    finish
  end

  def scaffold(locale)
    abort 'informe o locale, ex: scaffold es' if locale.to_s.empty?

    target = File.join(FE_FORK, locale)
    abort "#{target} ja existe" if Dir.exist?(target)

    scaffold_frontend(locale, target)
    scaffold_backend(locale)

    puts "traduza os valores; chaves nao traduzidas caem no fallback em #{REFERENCE_LOCALE}"
  end

  private

  def scaffold_frontend(_locale, target)
    FileUtils.mkdir_p(target)
    reference = Dir[File.join(FE_FORK, REFERENCE_LOCALE, '*.json')]
    reference.each { |path| FileUtils.cp(path, File.join(target, File.basename(path))) }
    puts "criado #{target}/ com #{reference.size} arquivos copiados de #{REFERENCE_LOCALE}"
  end

  def scaffold_backend(locale)
    Dir["config/locales/fazer_ai*.#{REFERENCE_LOCALE}.yml"].each do |path|
      copy = path.sub(".#{REFERENCE_LOCALE}.yml", ".#{locale}.yml")
      tree = YAML.safe_load_file(path, aliases: true)
      body = { locale => tree.values.first }.to_yaml(line_width: -1).delete_prefix("---\n")
      File.write(copy, header(path) + body)
      puts "criado #{copy}"
    end
  end

  def capture(*)
    out, _err, status = Open3.capture3(*)
    status.success? ? out : ''
  end

  def header(path)
    File.readlines(path).take_while { |line| line.start_with?('#') }.join
  end

  def fork_locales
    @fork_locales ||= Dir["#{FE_FORK}/*"].select { |path| File.directory?(path) }.map { |path| File.basename(path) }.sort
  end

  def flatten(obj, prefix = '', acc = {})
    case obj
    when Hash then obj.each { |key, value| flatten(value, prefix.empty? ? key.to_s : "#{prefix}.#{key}", acc) }
    when Array then obj.each_with_index { |value, index| flatten(value, "#{prefix}[#{index}]", acc) }
    else acc[prefix] = obj
    end
    acc
  end

  def keys_in(paths)
    paths.sort.each_with_object({}) do |path, acc|
      if path.end_with?('.json')
        acc.merge!(flatten(JSON.parse(File.read(path))))
      else
        # YAML locale files nest everything under the locale itself; drop that
        # root so keys are comparable across languages.
        tree = YAML.safe_load_file(path, aliases: true)
        acc.merge!(flatten(tree.values.first))
      end
    end
  end

  # Overrides are upstream keys we replace, so they are deliberately absent from
  # the fork's own key set and never count towards translation coverage.
  def fork_keys(locale)
    paths = Dir["#{FE_FORK}/#{locale}/*.json"].reject { |path| File.basename(path) == OVERRIDES }
    keys_in(paths).merge(keys_in(Dir["config/locales/fazer_ai*.#{locale}.yml"]))
  end

  def override_keys(locale)
    path = File.join(FE_FORK, locale, OVERRIDES)
    File.exist?(path) ? keys_in([path]) : {}
  end

  def check_reference_locale_exists
    return if fork_locales.include?(REFERENCE_LOCALE)

    @errors << "#{FE_FORK}/#{REFERENCE_LOCALE} nao existe; ele e a referencia de chaves e o alvo do fallback"
  end

  # A fork key living in both trees means someone edited an upstream file.
  def check_fork_keys_are_not_duplicated_upstream
    fork_locales.each do |locale|
      upstream = keys_in(Dir["#{FE_UPSTREAM}/#{locale}/*.json"])
      duplicated = fork_keys(locale).keys & upstream.keys
      unless duplicated.empty?
        @errors << "#{locale}: #{duplicated.size} chaves do fork tambem existem no upstream (#{duplicated.first(3).join(', ')})"
      end

      # The mirror case: an override that upstream does not define replaces
      # nothing, so it belongs in a regular fork file instead.
      dangling = override_keys(locale).keys - upstream.keys
      next if dangling.empty?

      @errors << "#{locale}: #{dangling.size} overrides nao existem no upstream (#{dangling.first(3).join(', ')})"
    end
  end

  # Anything translated in another language but absent from the reference is
  # unreachable: no component can render a key that `en` never defines.
  def check_every_key_exists_in_reference
    return unless fork_locales.include?(REFERENCE_LOCALE)

    reference = fork_keys(REFERENCE_LOCALE).keys
    (fork_locales - [REFERENCE_LOCALE]).each do |locale|
      orphans = fork_keys(locale).keys - reference
      next if orphans.empty?

      @errors << "#{locale}: #{orphans.size} chaves nao existem em #{REFERENCE_LOCALE} (#{orphans.first(3).join(', ')})"
    end
  end

  def check_upstream_indexes_ignore_the_fork
    Dir["#{FE_UPSTREAM}/*/index.js"].each do |path|
      next unless File.read(path).include?('fazer-ai')

      @errors << "#{path} referencia a arvore do fork; o merge acontece em i18n/index.js"
    end
  end

  def report_coverage
    return unless fork_locales.include?(REFERENCE_LOCALE)

    total = fork_keys(REFERENCE_LOCALE).size
    puts "chaves do fork em #{REFERENCE_LOCALE}: #{total}"
    (fork_locales - [REFERENCE_LOCALE]).each do |locale|
      translated = (fork_keys(locale).keys & fork_keys(REFERENCE_LOCALE).keys).size
      puts format('  %<locale>-8s %<done>4d/%<total>d traduzidas (%<percent>d%%)',
                  locale: locale, done: translated, total: total, percent: (translated * 100.0 / total).round)
    end
  end

  def finish
    if @errors.empty?
      puts 'ok'
      exit 0
    end
    @errors.each { |error| puts "erro: #{error}" }
    exit 1
  end
end

command = ARGV[0] || 'check'
case command
when 'check' then ForkTranslations.new.check
when 'drift'
  base_index = ARGV.index('--base')
  ForkTranslations.new.drift(base_index ? ARGV[base_index + 1] : UPSTREAM_BASE)
when 'scaffold' then ForkTranslations.new.scaffold(ARGV[1])
else abort "comando desconhecido: #{command} (use check, drift ou scaffold)"
end
