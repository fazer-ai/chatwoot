# == Schema Information
#
# Table name: operations_notification_acks
#
#  id                         :bigint           not null, primary key
#  acknowledged_at            :datetime         not null
#  ip                         :string
#  user_agent                 :string
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  operations_notification_id :bigint           not null
#  user_id                    :bigint           not null
#
# Indexes
#
#  idx_ops_notif_acks_unique                         (operations_notification_id,user_id) UNIQUE
#  index_operations_notification_acks_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (operations_notification_id => operations_notifications.id) ON DELETE => cascade
#  fk_rails_...  (user_id => users.id)
#
class OperationsNotificationAck < ApplicationRecord
  belongs_to :operations_notification
  belongs_to :user
  belongs_to :account

  validates :acknowledged_at, presence: true
  validates :operations_notification_id, uniqueness: { scope: :user_id }
end
