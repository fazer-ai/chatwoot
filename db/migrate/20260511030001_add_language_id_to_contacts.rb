class AddLanguageIdToContacts < ActiveRecord::Migration[7.1]
  def change
    add_reference :contacts, :language, null: true, foreign_key: true
  end
end
