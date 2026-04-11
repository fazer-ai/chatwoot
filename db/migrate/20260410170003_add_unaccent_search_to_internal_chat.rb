class AddUnaccentSearchToInternalChat < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up # rubocop:disable Metrics/MethodLength
    enable_extension 'unaccent' unless extension_enabled?('unaccent')

    execute <<~SQL.squish
      CREATE OR REPLACE FUNCTION f_unaccent(text)
        RETURNS text
        LANGUAGE sql
        IMMUTABLE
        PARALLEL SAFE
        STRICT
        AS $func$ SELECT public.unaccent('public.unaccent', $1) $func$
    SQL

    execute <<~SQL.squish
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ic_messages_content_unaccent_trgm
        ON internal_chat_messages USING gin (f_unaccent(content) gin_trgm_ops)
    SQL

    execute <<~SQL.squish
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ic_channels_name_unaccent_trgm
        ON internal_chat_channels USING gin (f_unaccent(name) gin_trgm_ops)
    SQL

    execute <<~SQL.squish
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_ic_channels_description_unaccent_trgm
        ON internal_chat_channels USING gin (f_unaccent(description) gin_trgm_ops)
    SQL

    execute <<~SQL.squish
      CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_users_name_unaccent_trgm
        ON users USING gin (f_unaccent(name) gin_trgm_ops)
    SQL
  end

  def down
    execute 'DROP INDEX CONCURRENTLY IF EXISTS idx_users_name_unaccent_trgm'
    execute 'DROP INDEX CONCURRENTLY IF EXISTS idx_ic_channels_description_unaccent_trgm'
    execute 'DROP INDEX CONCURRENTLY IF EXISTS idx_ic_channels_name_unaccent_trgm'
    execute 'DROP INDEX CONCURRENTLY IF EXISTS idx_ic_messages_content_unaccent_trgm'
    execute 'DROP FUNCTION IF EXISTS f_unaccent(text)'
  end
end
