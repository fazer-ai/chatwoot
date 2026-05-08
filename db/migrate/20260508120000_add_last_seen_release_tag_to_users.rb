class AddLastSeenReleaseTagToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :last_seen_release_tag, :string

    reversible do |dir|
      dir.up { bootstrap_existing_users }
    end
  end

  private

  # Existing users shouldn't be spammed with the historical changelog modal
  # on the first login after this feature ships. Mark them as having seen the
  # latest release at deploy time; only future releases trigger the modal.
  def bootstrap_existing_users
    catalog_path = Rails.root.join('config/release_notes.yml')
    return unless File.exist?(catalog_path)

    entries = YAML.safe_load(File.read(catalog_path), permitted_classes: [Time, Date, DateTime])
    latest_tag = Array(entries).first&.dig('tag')
    return if latest_tag.blank?

    execute(sanitize_sql_for_update(latest_tag))
  end

  def sanitize_sql_for_update(tag)
    quoted = ActiveRecord::Base.connection.quote(tag)
    "UPDATE users SET last_seen_release_tag = #{quoted} WHERE last_seen_release_tag IS NULL"
  end
end
