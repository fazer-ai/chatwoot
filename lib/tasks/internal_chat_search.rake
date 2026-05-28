# Creates the `f_unaccent` wrapper function used by the internal chat search
# functional GIN trigram indexes.
#
# `schema.rb` can only capture `enable_extension`/`create_table`/indexes, not
# `CREATE FUNCTION`, so without this hook `db:schema:load` would fail trying to
# create indexes that reference the non-existent `f_unaccent` function.
#
# These tasks are wired from the Rakefile (after `Rails.application.load_tasks`):
# - `ensure_search_functions` runs BEFORE `db:schema:load` to create the function
#   in the target database.
# - `inject_schema_functions` runs AFTER `db:schema:dump` to re-insert the
#   `execute <<~SQL CREATE OR REPLACE FUNCTION ...` block the dumper drops.

SCHEMA_FUNCTION_MARKER = 'CREATE OR REPLACE FUNCTION f_unaccent'.freeze

SCHEMA_FUNCTION_BLOCK = <<~RUBY.gsub(/^(?=.)/, '  ').freeze
  # Custom SQL functions (required before index creation)
  execute <<~SQL
    CREATE OR REPLACE FUNCTION f_unaccent(text)
      RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
      AS $func$ SELECT public.unaccent('public.unaccent', $1) $func$
  SQL
RUBY

# rubocop:disable Metrics/BlockLength
namespace :db do
  namespace :internal_chat do
    desc 'Ensure the f_unaccent wrapper function required by internal chat search indexes exists'
    task ensure_search_functions: :load_config do
      # `db:schema:load` in development iterates over BOTH the development AND
      # test databases (see `ActiveRecord::Tasks::DatabaseTasks.each_current_environment`),
      # so we need to install the f_unaccent function on every relevant config,
      # not just the currently-connected one.
      original_db_config = ActiveRecord::Base.connection_db_config
      environments = [Rails.env]
      environments << 'test' if Rails.env.development? && !ENV['SKIP_TEST_DATABASE'] && !ENV['DATABASE_URL']

      environments.each do |env|
        ActiveRecord::Base.configurations.configs_for(env_name: env).each do |db_config|
          ActiveRecord::Base.establish_connection(db_config)
          conn = ActiveRecord::Base.connection
          conn.execute('CREATE EXTENSION IF NOT EXISTS unaccent')
          conn.execute(<<~SQL.squish)
            CREATE OR REPLACE FUNCTION public.f_unaccent(text)
              RETURNS text
              LANGUAGE sql
              IMMUTABLE
              PARALLEL SAFE
              STRICT
              AS $func$ SELECT public.unaccent('public.unaccent', $1) $func$
          SQL
        end
      end
    ensure
      ActiveRecord::Base.establish_connection(original_db_config) if original_db_config
    end

    desc 'Inject the f_unaccent function block into db/schema.rb (run after db:schema:dump)'
    task inject_schema_functions: :environment do
      schema_path = Rails.root.join('db/schema.rb')
      next unless File.exist?(schema_path)

      content = File.read(schema_path)
      next if content.include?(SCHEMA_FUNCTION_MARKER)

      new_content = content.sub(
        /(^  enable_extension "[^"]+"\n)(\n  create_table)/,
        "\\1\n#{SCHEMA_FUNCTION_BLOCK}\\2"
      )

      if new_content == content
        warn '[inject_schema_functions] Could not find insertion point in db/schema.rb ' \
             '(last enable_extension + create_table); f_unaccent block NOT injected. Add it manually.'
        next
      end

      File.write(schema_path, new_content)
      puts '-- Injected f_unaccent function block into db/schema.rb'
    end
  end
end
# rubocop:enable Metrics/BlockLength
