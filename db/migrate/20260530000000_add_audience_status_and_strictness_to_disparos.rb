class AddAudienceStatusAndStrictnessToDisparos < ActiveRecord::Migration[7.1]
  def change
    # conversation_status: which conversation statuses enter the audience.
    #   0 = open (only conversations.status == open), 1 = all (no status filter).
    add_column :disparos, :conversation_status, :integer, null: false, default: 0

    # strictness_mode: padrao (apply all conditional skips) vs minimo (skip ~5
    # conditional skips). Added now so the data model is ready; the
    # EligibilityEngine consumes it in a later task.
    add_column :disparos, :strictness_mode, :integer, null: false, default: 0
  end
end
