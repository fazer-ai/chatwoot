# Creates the `f_unaccent` wrapper function used by the internal chat search
# functional GIN trigram indexes.
#
# `schema.rb` can only capture `enable_extension`/`create_table`/indexes, not
# `CREATE FUNCTION`, so without this hook `db:schema:load` would fail trying to
# create indexes that reference the non-existent `f_unaccent` function.
#
# This task is wired as a prerequisite of `db:schema:load` from the Rakefile
# (after `Rails.application.load_tasks`), so both task definitions are
# guaranteed to be present when the prereq is added.

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
  end
end
