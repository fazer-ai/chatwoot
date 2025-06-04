class CreateTabulationSubcategories < ActiveRecord::Migration[7.1]
  def change
    create_table :tabulation_subcategories do |t|
      t.string :name, null: false
      t.boolean :active, default: true, null: false
      t.bigint :tabulation_category_id, null: false
      t.bigint :account_id, null: false
      t.timestamps
    end
    add_index :tabulation_subcategories, :tabulation_category_id, name: 'index_tab_subcats_on_category_id'
    add_index :tabulation_subcategories, :account_id
    add_index :tabulation_subcategories, [:name, :tabulation_category_id], name: 'index_tab_subcats_on_name_and_category', unique: true
  end
end
