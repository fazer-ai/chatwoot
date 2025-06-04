class CreateTabulationRecords < ActiveRecord::Migration[7.1]
  def change
    create_table :tabulation_records do |t|
      t.bigint :conversation_id, null: false
      t.bigint :tabulation_category_id, null: false
      t.bigint :tabulation_subcategory_id, null: false
      t.bigint :account_id, null: false
      t.integer :action_type, default: 0, null: false
      t.timestamps
    end
    add_index :tabulation_records, :conversation_id
    add_index :tabulation_records, :tabulation_category_id
    add_index :tabulation_records, :tabulation_subcategory_id, name: 'index_tab_records_on_subcategory_id'
    add_index :tabulation_records, :account_id
  end
end
