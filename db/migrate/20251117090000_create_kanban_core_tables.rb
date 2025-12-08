class CreateKanbanCoreTables < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    create_table :kanban_boards do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.jsonb :settings, default: {}, null: false
      t.integer :steps_order, array: true, default: []
      t.timestamps
    end

    add_index :kanban_boards, [:account_id, :name], unique: true
    add_index :kanban_boards, [:account_id, :created_at]
    add_index :kanban_boards, [:account_id, :updated_at]

    create_table :kanban_board_steps do |t|
      t.references :board, null: false, foreign_key: { to_table: :kanban_boards }
      t.string :name, null: false
      t.text :description
      t.string :color, null: false, default: '#475569'
      t.integer :tasks_count, null: false, default: 0
      t.boolean :cancelled, null: false, default: false
      t.timestamps
    end

    create_table :kanban_tasks do |t|
      t.references :account, null: false, foreign_key: true
      t.references :board, null: false, foreign_key: { to_table: :kanban_boards }
      t.references :board_step, null: false, foreign_key: { to_table: :kanban_board_steps }
      t.references :created_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :title, null: false
      t.text :description
      t.string :priority, null: false, default: 'normal'
      t.datetime :start_date
      t.datetime :end_date
      t.timestamps
    end

    add_index :kanban_tasks, [:account_id, :created_at]
    add_index :kanban_tasks, [:board_id, :board_step_id]
    add_index :kanban_tasks, [:board_id, :priority]
    add_index :kanban_tasks, [:board_step_id, :priority]
    add_index :kanban_tasks, :priority

    add_reference :conversations, :kanban_task, foreign_key: { to_table: :kanban_tasks }

    create_table :kanban_task_contacts do |t|
      t.references :task, null: false, foreign_key: { to_table: :kanban_tasks }
      t.references :contact, null: false, foreign_key: true
      t.timestamps
    end

    add_index :kanban_task_contacts, [:task_id, :contact_id], unique: true

    create_table :kanban_task_agents do |t|
      t.references :task, null: false, foreign_key: { to_table: :kanban_tasks }
      t.references :agent, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :kanban_task_agents, [:task_id, :agent_id], unique: true

    create_table :kanban_audit_events do |t|
      t.references :account, null: false, foreign_key: true
      t.references :task, null: false, foreign_key: { to_table: :kanban_tasks }
      t.references :performed_by, foreign_key: { to_table: :users }
      t.string :action, null: false
      t.jsonb :metadata, default: {}, null: false
      t.timestamps
    end

    add_index :kanban_audit_events, [:account_id, :created_at]

    create_table :kanban_board_agents do |t|
      t.references :board, null: false, foreign_key: { to_table: :kanban_boards }
      t.references :agent, null: false, foreign_key: { to_table: :users }
      t.timestamps
    end

    add_index :kanban_board_agents, [:board_id, :agent_id], unique: true

    create_table :kanban_board_inboxes do |t|
      t.references :board, null: false, foreign_key: { to_table: :kanban_boards }
      t.references :inbox, null: false, foreign_key: true
      t.timestamps
    end

    add_index :kanban_board_inboxes, [:board_id, :inbox_id], unique: true

    create_table :kanban_account_user_preferences do |t|
      t.references :account_user, null: false, foreign_key: true, index: { unique: true }
      t.jsonb :preferences, default: {}, null: false
      t.timestamps
    end
  end
end
