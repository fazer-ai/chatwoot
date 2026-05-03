class MakeFunnelStagesGlobal < ActiveRecord::Migration[7.1]
  def up
    # Keep one row per name (lowest id) so we don't blow the unique index when account_id goes away.
    execute(<<~SQL.squish)
      DELETE FROM funnel_stages
      WHERE id NOT IN (
        SELECT MIN(id) FROM funnel_stages GROUP BY name
      )
    SQL

    name_idx = :index_funnel_stages_on_account_id_and_name
    position_idx = :index_funnel_stages_on_account_id_and_position

    remove_index :funnel_stages, name: name_idx if index_exists?(:funnel_stages, [:account_id, :name], name: name_idx)
    remove_index :funnel_stages, name: position_idx if index_exists?(:funnel_stages, [:account_id, :position], name: position_idx)

    remove_reference :funnel_stages, :account, foreign_key: { on_delete: :cascade }, index: false

    add_index :funnel_stages, :name, unique: true
    add_index :funnel_stages, :position
  end

  def down
    add_reference :funnel_stages, :account, foreign_key: { on_delete: :cascade }, index: false

    # Best-effort: stamp every existing row with the lowest account id so the column can stay NOT NULL.
    fallback_account_id = Account.order(:id).limit(1).pick(:id)
    execute("UPDATE funnel_stages SET account_id = #{fallback_account_id}") if fallback_account_id

    change_column_null :funnel_stages, :account_id, false

    remove_index :funnel_stages, :name if index_exists?(:funnel_stages, :name)
    remove_index :funnel_stages, :position if index_exists?(:funnel_stages, :position)

    add_index :funnel_stages, [:account_id, :name], unique: true, name: :index_funnel_stages_on_account_id_and_name
    add_index :funnel_stages, [:account_id, :position], name: :index_funnel_stages_on_account_id_and_position
  end
end
