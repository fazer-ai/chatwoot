# Creates the `f_unaccent` wrapper function used by the internal chat search
# functional GIN trigram indexes.
#
# `schema.rb` can only capture `enable_extension`/`create_table`/indexes, not
# `CREATE FUNCTION`, so without this hook `db:schema:load` would fail trying to
# create indexes that reference the non-existent `f_unaccent` function.
#
# Declared as a prerequisite of `db:schema:load` via Rake task augmentation
# (re-opening `db:schema:load` to add the dependency), so this works regardless
# of the order in which Rake files are loaded by Rails.

namespace :db do
  namespace :internal_chat do
    desc 'Ensure the f_unaccent wrapper function required by internal chat search indexes exists'
    task ensure_search_functions: :load_config do
      puts '[internal_chat_search] ensure_search_functions running'
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

  namespace :schema do
    task load: 'db:internal_chat:ensure_search_functions'
  end
end
