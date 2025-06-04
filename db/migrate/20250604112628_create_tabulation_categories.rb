class CreateTabulationCategories < ActiveRecord::Migration[7.1]
  def change
    create_table :tabulation_categories do |t|
      t.string :name, null: false
      t.string :color, default: '#1f93ff', null: false
      t.boolean :active, default: true, null: false
      t.bigint :account_id, null: false
      t.timestamps
    end
    add_index :tabulation_categories, :account_id
    add_index :tabulation_categories, [:name, :account_id], unique: true
  end
end
