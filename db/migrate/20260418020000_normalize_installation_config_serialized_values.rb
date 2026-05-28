class NormalizeInstallationConfigSerializedValues < ActiveRecord::Migration[7.1]
  # Rails' YAML coder expects the jsonb column to hold a JSON-encoded YAML
  # string. Some rows were written as native jsonb objects by older code paths,
  # which raises "no implicit conversion of Hash into String" on read. Convert
  # every `object`-shaped row to the YAML-string shape the coder produces.
  def up
    rows = execute(
      "SELECT id, serialized_value FROM installation_configs WHERE jsonb_typeof(serialized_value) = 'object'"
    ).to_a

    rows.each do |row|
      hash = JSON.parse(row['serialized_value']).with_indifferent_access
      yaml = YAML.dump(hash)
      execute(
        ActiveRecord::Base.sanitize_sql_array(
          ['UPDATE installation_configs SET serialized_value = to_jsonb(?::text) WHERE id = ?', yaml, row['id']]
        )
      )
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
