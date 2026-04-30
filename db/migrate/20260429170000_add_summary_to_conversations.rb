class AddSummaryToConversations < ActiveRecord::Migration[7.1]
  def change
    add_column :conversations, :summary, :text
  end
end
