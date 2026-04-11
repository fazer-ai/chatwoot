# Creates the `f_unaccent` wrapper function used by the internal chat search
# functional GIN trigram indexes.
#
# `schema.rb` can only capture `enable_extension`/`create_table`/indexes, not
# `CREATE FUNCTION`, so without this hook `db:schema:load` would fail trying to
# create indexes that reference the non-existent `f_unaccent` function.
#
# The task is wired as a prerequisite of `db:schema:load` so the function is
# always present in dev/test/CI before the schema is loaded.

namespace :db do
  namespace :internal_chat do
    desc 'Ensure the f_unaccent wrapper function required by internal chat search indexes exists'
    task ensure_search_functions: :load_config do
      ActiveRecord::Base.connection.execute('CREATE EXTENSION IF NOT EXISTS unaccent')
      ActiveRecord::Base.connection.execute(<<~SQL.squish)
        CREATE OR REPLACE FUNCTION f_unaccent(text)
          RETURNS text
          LANGUAGE sql
          IMMUTABLE
          PARALLEL SAFE
          STRICT
          AS $func$ SELECT public.unaccent('public.unaccent', $1) $func$
      SQL
    end
  end
end

Rake::Task['db:schema:load'].enhance(['db:internal_chat:ensure_search_functions']) if Rake::Task.task_defined?('db:schema:load')
