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
      conn = ActiveRecord::Base.connection
      puts "[internal_chat_search] connected to: #{conn.current_database}"
      conn.execute('CREATE EXTENSION IF NOT EXISTS unaccent')
      conn.execute(<<~SQL.squish)
        CREATE OR REPLACE FUNCTION f_unaccent(text)
          RETURNS text
          LANGUAGE sql
          IMMUTABLE
          PARALLEL SAFE
          STRICT
          AS $func$ SELECT public.unaccent('public.unaccent', $1) $func$
      SQL
      exists = conn.select_value("SELECT 1 FROM pg_proc WHERE proname = 'f_unaccent'")
      puts "[internal_chat_search] f_unaccent created? #{exists.inspect}"
    end
  end

  namespace :schema do
    task load: 'db:internal_chat:ensure_search_functions'
  end
end
