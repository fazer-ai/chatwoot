class CreateTicketUpdates < ActiveRecord::Migration[7.1]
  def change
    create_table :ticket_updates do |t|
      t.references :ticket, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.references :user, null: true, foreign_key: true, index: true
      t.string :actor_name, null: false
      t.text :body, null: false

      t.timestamps
    end
  end
end
