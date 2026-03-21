class CreateInternalChatCategories < ActiveRecord::Migration[7.0]
  def change
    create_table :internal_chat_categories do |t|
      t.references :account, null: false, index: true
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :internal_chat_categories, [:account_id, :name], unique: true
    add_index :internal_chat_categories, [:account_id, :position]
  end
end
