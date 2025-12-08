# frozen_string_literal: true

# == Schema Information
#
# Table name: kanban_audit_events
#
#  id              :bigint           not null, primary key
#  action          :string           not null
#  metadata        :jsonb            not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  performed_by_id :bigint
#  task_id         :bigint           not null
#
# Indexes
#
#  index_kanban_audit_events_on_account_id                 (account_id)
#  index_kanban_audit_events_on_account_id_and_created_at  (account_id,created_at)
#  index_kanban_audit_events_on_performed_by_id            (performed_by_id)
#  index_kanban_audit_events_on_task_id                    (task_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (performed_by_id => users.id)
#  fk_rails_...  (task_id => kanban_tasks.id)
#
class FazerAi::Kanban::AuditEvent < ApplicationRecord
  self.table_name = 'kanban_audit_events'

  belongs_to :account
  belongs_to :task,
             class_name: 'FazerAi::Kanban::Task',
             inverse_of: :audit_events
  belongs_to :actor,
             class_name: 'User',
             inverse_of: :kanban_audit_events,
             foreign_key: :performed_by_id,
             optional: true

  validates :action, presence: true
end
