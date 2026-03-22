class CreateInternalChatChannelTeams < ActiveRecord::Migration[7.0]
  def change
    create_table :internal_chat_channel_teams do |t|
      t.references :internal_chat_channel, null: false, foreign_key: true, index: false
      t.references :team, null: false, foreign_key: true
      t.timestamps
    end
    add_index :internal_chat_channel_teams, [:internal_chat_channel_id, :team_id],
              unique: true, name: 'idx_ic_channel_teams_channel_team'
  end
end
