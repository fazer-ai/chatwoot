# Feedback tickets opened from the conversation ⋮ menu (Auris-only feature).
# Each ticket is a local mirror of a task on the ClickUp Feedback list — the
# ClickUp side stays the canonical source for status changes, comments, and
# attachments, but we keep a local record so the operator can look at "Meus
# Tickets" without hitting the ClickUp API on every page load.
class CreateTickets < ActiveRecord::Migration[7.1]
  def change # rubocop:disable Metrics/MethodLength
    create_table :tickets do |t|
      # Ownership + context.
      t.references :account, null: false, foreign_key: { on_delete: :cascade }, index: true
      # `user_id` is nullable so a ticket survives an agent being removed from
      # the account — historical audit for the ops team, and Meus Tickets can
      # still resolve the ticket by account scope for the manager view.
      t.references :user, foreign_key: { on_delete: :nullify }, index: true
      t.string :context_type, null: false
      t.bigint :context_id, null: false
      # `conversation_id` is denormalized off the context (a Message belongs to
      # a Conversation) so the Meus Tickets list can filter/preview without
      # loading the Message row.
      t.references :conversation, foreign_key: { on_delete: :cascade }, index: true

      # ClickUp side. Nullable until the async CreateTaskJob completes.
      t.string :clickup_task_id
      t.string :clickup_task_url
      t.string :clickup_status_id
      t.string :clickup_status_name

      # Sync bookkeeping — retry state for the CreateTaskJob and the last
      # error we saw so a failed sync surfaces in Super Admin without opening
      # the Sidekiq dashboard.
      t.integer :sync_status, default: 0, null: false
      t.integer :sync_attempts, default: 0, null: false
      t.text :sync_error

      # User inputs — copied verbatim into the ClickUp custom fields on the
      # first successful sync. Kept locally so the Meus Tickets detail modal
      # doesn't need a ClickUp round-trip to show the operator what they wrote.
      t.text :relatar_problema, null: false
      t.text :comportamento_esperado

      # Response from the ops team on the ClickUp side, flowed back via the
      # taskCustomFieldUpdated webhook. `resposta_notified_at` guards against
      # sending duplicate bell notifications when the same webhook is retried.
      t.text :resposta_para_cliente
      t.datetime :resposta_notified_at

      t.timestamps
    end

    # Meus Tickets queries: (account, user, created_at) drives the agent view;
    # (account, created_at) drives the manager view.
    add_index :tickets, [:account_id, :user_id, :created_at]
    add_index :tickets, [:account_id, :created_at]
    # Prevents opening two tickets on the same message from a single tab race.
    # The service layer also checks — this is the last-line defense.
    add_index :tickets, [:context_type, :context_id]
    # Webhook lookup: ClickUp posts task_id, we resolve to Ticket. Unique
    # partial index because clickup_task_id is nil while sync is pending.
    add_index :tickets, :clickup_task_id, unique: true, where: 'clickup_task_id IS NOT NULL'
  end
end
