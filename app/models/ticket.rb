# == Schema Information
#
# Table name: tickets
#
#  id                     :bigint           not null, primary key
#  clickup_status_name    :string
#  clickup_task_url       :string
#  comportamento_esperado :text
#  context_type           :string           not null
#  relatar_problema       :text             not null
#  resposta_notified_at   :datetime
#  resposta_para_cliente  :text
#  sync_attempts          :integer          default(0), not null
#  sync_error             :text
#  sync_status            :integer          default("pending_sync"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  clickup_status_id      :string
#  clickup_task_id        :string
#  context_id             :bigint           not null
#  conversation_id        :bigint
#  user_id                :bigint
#
# Indexes
#
#  index_tickets_on_account_id                             (account_id)
#  index_tickets_on_account_id_and_created_at              (account_id,created_at)
#  index_tickets_on_account_id_and_user_id_and_created_at  (account_id,user_id,created_at)
#  index_tickets_on_clickup_task_id                        (clickup_task_id) UNIQUE WHERE (clickup_task_id IS NOT NULL)
#  index_tickets_on_context_type_and_context_id            (context_type,context_id)
#  index_tickets_on_conversation_id                        (conversation_id)
#  index_tickets_on_user_id                                (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class Ticket < ApplicationRecord
  belongs_to :account
  # user (agent who opened the ticket) is nullable so a removed agent doesn't
  # take historic tickets down with them — manager view + audit still work.
  belongs_to :user, optional: true
  belongs_to :conversation, optional: true
  belongs_to :context, polymorphic: true

  # 3-state machine that tracks the ClickUp create-task job.
  # - `pending_sync`: local ticket exists, CreateTaskJob has not (yet) landed
  #   a ClickUp task id on it. Blocks comment/attachment jobs.
  # - `synced`: happy path. clickup_task_id, url, and status are populated.
  # - `sync_failed`: the CreateTaskJob exhausted its retries. Ticket stays
  #   readable in Meus Tickets so the agent knows something went wrong; the
  #   ops team can retry from Super Admin (PR3).
  enum :sync_status, {
    pending_sync: 0,
    synced: 1,
    sync_failed: 2
  }, prefix: :sync

  validates :context_type, presence: true, inclusion: { in: %w[Message] }
  validates :context_id, presence: true
  validates :relatar_problema, presence: true, length: { maximum: 5000 }
  validates :comportamento_esperado, length: { maximum: 5000 }, allow_blank: true

  scope :for_user, ->(u) { where(user_id: u.id) }
  scope :for_account, ->(a) { where(account_id: a.id) }
  scope :recent_first, -> { order(created_at: :desc) }

  # Serialization used by the ActionCable broadcast when the webhook applies
  # a status/response change. The frontend Vuex store consumes the same
  # shape as the JBuilder index/show responses so the record swaps in place.
  def push_event_data
    core_fields.merge(clickup_fields).merge(
      resposta_para_cliente: resposta_para_cliente,
      resposta_notified_at: resposta_notified_at,
      user: user_push_event_data,
      created_at: created_at,
      updated_at: updated_at
    )
  end

  private

  def core_fields
    {
      id: id,
      account_id: account_id,
      conversation_id: conversation_id,
      conversation_display_id: conversation&.display_id,
      message_id: context_type == 'Message' ? context_id : nil,
      relatar_problema: relatar_problema,
      comportamento_esperado: comportamento_esperado,
      sync_status: sync_status,
      sync_error: sync_error
    }
  end

  def clickup_fields
    {
      clickup_task_id: clickup_task_id,
      clickup_task_url: clickup_task_url,
      clickup_status_id: clickup_status_id,
      clickup_status_name: clickup_status_name
    }
  end

  def user_push_event_data
    return nil if user.blank?

    { id: user.id, name: user.name, email: user.email }
  end
end
