class CreateFunnelStages < ActiveRecord::Migration[7.1]
  def change
    create_table :funnel_stages do |t|
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.string :name, null: false
      t.text :description
      t.integer :position, null: false, default: 0
      t.boolean :closed, null: false, default: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :funnel_stages, [:account_id, :position]
    add_index :funnel_stages, [:account_id, :name], unique: true
  end
end
