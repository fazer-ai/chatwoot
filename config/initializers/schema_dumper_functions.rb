# Extends the Rails schema dumper to include custom SQL functions that are
# required by indices but not natively supported by schema.rb format.
#
# Without this, db:schema:load (used by db:test:prepare) fails because
# schema.rb references indices that depend on f_unaccent() but the function
# definition is lost during the dump (schema.rb only captures tables,
# indices, and extensions, not custom functions).
module SchemaDumperFunctions
  private

  def extensions(stream)
    super
    dump_custom_functions(stream)
  end

  def dump_custom_functions(stream)
    stream.puts
    stream.puts '  # Custom SQL functions (required before index creation)'
    stream.puts '  execute <<~SQL'
    stream.puts '    CREATE OR REPLACE FUNCTION f_unaccent(text)'
    stream.puts '      RETURNS text LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT'
    stream.puts "      AS $func$ SELECT public.unaccent('public.unaccent', $1) $func$"
    stream.puts '  SQL'
  end
end

ActiveRecord::SchemaDumper.prepend(SchemaDumperFunctions)
