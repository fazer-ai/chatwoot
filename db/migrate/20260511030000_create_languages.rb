class CreateLanguages < ActiveRecord::Migration[7.1]
  # `languages` is a small, install-wide catalog used to tag a contact's
  # preferred language. Managed only via direct DB inserts — no CRUD UI.
  def up
    create_table :languages do |t|
      t.string :code, null: false
      t.string :name, null: false
      t.integer :position, default: 0, null: false
      t.timestamps
    end
    add_index :languages, :code, unique: true
    add_index :languages, :position

    seed_default_languages
  end

  def down
    drop_table :languages
  end

  private

  def seed_default_languages
    quoted_now = ActiveRecord::Base.connection.quote(Time.zone.now)
    rows = [
      { code: 'pt-br', name: 'Português', position: 1 },
      { code: 'en-us', name: 'Inglês',    position: 2 },
      { code: 'es-es', name: 'Espanhol',  position: 3 },
      { code: 'fr-fr', name: 'Francês',   position: 4 }
    ]

    rows.each do |attrs|
      quoted_code = ActiveRecord::Base.connection.quote(attrs[:code])
      quoted_name = ActiveRecord::Base.connection.quote(attrs[:name])
      execute(
        'INSERT INTO languages (code, name, position, created_at, updated_at) ' \
        "VALUES (#{quoted_code}, #{quoted_name}, #{attrs[:position]}, #{quoted_now}, #{quoted_now})"
      )
    end
  end
end
