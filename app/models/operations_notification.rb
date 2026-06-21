# == Schema Information
#
# Table name: operations_notifications
#
#  id             :bigint           not null, primary key
#  audience_type  :integer          default("all_users"), not null
#  audience_value :string
#  body           :text             not null
#  deleted_at     :datetime
#  expires_at     :datetime
#  published_at   :datetime
#  scope_type     :integer          default("all_accounts"), not null
#  severity       :integer          default("info"), not null
#  title          :string           not null
#  trigger_kind   :integer          default("immediate"), not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  account_id     :bigint
#  created_by_id  :bigint           not null
#
# Indexes
#
#  index_operations_notifications_on_account_id     (account_id)
#  index_operations_notifications_on_created_by_id  (created_by_id)
#  index_operations_notifications_on_deleted_at     (deleted_at)
#  index_operations_notifications_on_expires_at     (expires_at)
#  index_operations_notifications_on_published_at   (published_at)
#
class OperationsNotification < ApplicationRecord
  enum severity: { info: 0, emergency: 1 }
  enum scope_type: { all_accounts: 0, account: 1 }, _prefix: :scope
  enum audience_type: { all_users: 0, role: 1, specific_user: 2 }, _prefix: :audience
  enum trigger_kind: { immediate: 0, on_login: 1 }, _prefix: :trigger

  belongs_to :account, optional: true
  belongs_to :created_by, class_name: 'User'
  has_many :operations_notification_acks, dependent: :destroy

  validates :title, presence: true
  validates :body, presence: true
  validate :account_required_when_scoped_to_account
  validate :audience_value_required_when_targeted

  scope :active, -> { where(deleted_at: nil) }
  scope :published, lambda {
    where.not(published_at: nil)
         .where('expires_at IS NULL OR expires_at > ?', Time.current)
  }

  # Returns the relation of notifications that should be considered for a
  # given user/account pair: matches both the account-scope and the
  # audience constraints in a single query.
  def self.visible_for(user, account)
    user_role = AccountUser.find_by(account_id: account.id, user_id: user.id)&.role

    active.published
          .where('scope_type = ? OR (scope_type = ? AND account_id = ?)',
                 scope_types[:all_accounts], scope_types[:account], account.id)
          .where(
            <<~SQL.squish,
              audience_type = :all_users
              OR (audience_type = :role AND audience_value = :user_role)
              OR (audience_type = :specific_user AND audience_value = :user_id)
            SQL
            all_users: audience_types[:all_users],
            role: audience_types[:role],
            user_role: user_role,
            specific_user: audience_types[:specific_user],
            user_id: user.id.to_s
          )
          .order(created_at: :desc)
  end

  # Same as visible_for but excludes notifications already acknowledged.
  def self.pending_for(user, account)
    visible_for(user, account)
      .where.not(id: OperationsNotificationAck.where(user_id: user.id).select(:operations_notification_id))
  end

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  private

  def account_required_when_scoped_to_account
    return unless scope_account?
    return if account_id.present?

    errors.add(:account_id, 'is required when scope is "account"')
  end

  def audience_value_required_when_targeted
    return if audience_all_users?
    return if audience_value.present?

    errors.add(:audience_value, 'is required when audience is "role" or "specific_user"')
  end
end
