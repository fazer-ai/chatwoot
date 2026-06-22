# == Schema Information
#
# Table name: operations_notifications
#
#  id                :bigint           not null, primary key
#  account_ids       :bigint           default([]), not null, is an Array
#  audience_type     :integer          default("all_users"), not null
#  audience_user_ids :bigint           default([]), not null, is an Array
#  body              :text             not null
#  deleted_at        :datetime
#  expires_at        :datetime
#  published_at      :datetime
#  scope_type        :integer          default("all_accounts"), not null
#  severity          :integer          default("info"), not null
#  title             :string           not null
#  trigger_kind      :integer          default("immediate"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  created_by_id     :bigint           not null
#
# Indexes
#
#  index_operations_notifications_on_account_ids        (account_ids) USING gin
#  index_operations_notifications_on_audience_user_ids  (audience_user_ids) USING gin
#  index_operations_notifications_on_created_by_id      (created_by_id)
#  index_operations_notifications_on_deleted_at         (deleted_at)
#  index_operations_notifications_on_expires_at         (expires_at)
#  index_operations_notifications_on_published_at       (published_at)
#
class OperationsNotification < ApplicationRecord
  enum severity: { info: 0, emergency: 1 }
  enum scope_type: { all_accounts: 0, accounts: 1 }, _prefix: :scope
  # `specific_users` is the only audience type that consults
  # `audience_user_ids`; the role-based ones (agents / managers /
  # administrators) read from the `account_users.role` join.
  enum audience_type: {
    all_users: 0,
    agents: 1,
    managers: 2,
    administrators: 3,
    specific_users: 4
  }, _prefix: :audience
  enum trigger_kind: { immediate: 0, on_login: 1 }, _prefix: :trigger

  ROLE_AUDIENCE_TO_ACCOUNT_USER_ROLE = {
    'agents' => 'agent',
    'managers' => 'manager',
    'administrators' => 'administrator'
  }.freeze

  belongs_to :created_by, class_name: 'User'
  has_many :operations_notification_acks, dependent: :destroy

  validates :title, presence: true
  validates :body, presence: true
  validate :account_ids_required_when_scoped_to_accounts
  validate :audience_user_ids_required_when_specific_users
  validate :specific_users_require_account_scope

  # Push to ActionCable only when the operator marked the notification as
  # `immediate`. `on_login` ones rely on the frontend's onMounted
  # fetchPending — pushing them would force them onto users already
  # active, which contradicts the "wait until next login" intent.
  after_create_commit :broadcast_if_immediate

  scope :active, -> { where(deleted_at: nil) }
  scope :published, lambda {
    where.not(published_at: nil)
         .where('expires_at IS NULL OR expires_at > ?', Time.current)
  }

  # Convenience for the dashboard/form layer; we do NOT use a real
  # has_many because there is no join table — the list lives in the
  # `account_ids` array column.
  def accounts
    Account.where(id: account_ids)
  end

  def audience_users
    User.where(id: audience_user_ids)
  end

  # Returns the relation of notifications that should be considered for a
  # given user/account pair. Two-step filter: (a) the scope (all accounts
  # vs. an explicit list that must include the given account), and
  # (b) the audience (everyone in scope vs. a role-restricted slice vs.
  # an explicit user list). The role and specific-user variants both
  # require that the user actually belongs to one of the targeted
  # accounts, which the scope predicate already enforces.
  def self.visible_for(user, account)
    active.published
          .where(scope_sql, **scope_bindings(account))
          .where(audience_sql, **audience_bindings(user, account))
          .order(created_at: :desc)
  end

  # Same as visible_for but excludes notifications already acknowledged.
  def self.pending_for(user, account)
    visible_for(user, account)
      .where.not(id: OperationsNotificationAck.where(user_id: user.id).select(:operations_notification_id))
  end

  def self.scope_sql
    'scope_type = :all OR (scope_type = :scoped AND :account_id = ANY(account_ids))'
  end
  private_class_method :scope_sql

  def self.scope_bindings(account)
    { all: scope_types[:all_accounts], scoped: scope_types[:accounts], account_id: account.id }
  end
  private_class_method :scope_bindings

  def self.audience_sql
    <<~SQL.squish
      audience_type = :all_users
      OR (audience_type = :agents       AND :role = :agent_role)
      OR (audience_type = :managers     AND :role = :manager_role)
      OR (audience_type = :administrators AND :role = :admin_role)
      OR (audience_type = :specific_users AND :user_id = ANY(audience_user_ids))
    SQL
  end
  private_class_method :audience_sql

  def self.audience_bindings(user, account)
    role = AccountUser.find_by(account_id: account.id, user_id: user.id)&.role
    {
      all_users: audience_types[:all_users],
      agents: audience_types[:agents],
      managers: audience_types[:managers],
      administrators: audience_types[:administrators],
      specific_users: audience_types[:specific_users],
      role: role && AccountUser.roles[role],
      agent_role: AccountUser.roles['agent'],
      manager_role: AccountUser.roles['manager'],
      admin_role: AccountUser.roles['administrator'],
      user_id: user.id
    }
  end
  private_class_method :audience_bindings

  def soft_delete!
    update!(deleted_at: Time.current)
  end

  # Plain-text label used by the super-admin show page. We avoid linking
  # to the creator because `created_by` is a `SuperAdmin` (STI subclass
  # of `User`) and Rails' route helpers resolve by class name, producing
  # `super_admin_super_admin_path` — a route that does not exist.
  def created_by_display
    created_by&.available_name.presence || created_by&.email
  end

  # Human-readable list of targeted accounts for the super-admin show
  # page. Returns "—" for the all-accounts scope so the row is still
  # rendered (Administrate hides empty fields).
  def accounts_summary
    return '—' unless scope_accounts?

    accounts.pluck(:name).join(', ').presence || '—'
  end

  # Human-readable list of targeted users for the super-admin show page.
  # Only meaningful when audience_type is `specific_users`.
  def audience_users_summary
    return '—' unless audience_specific_users?

    audience_users
      .map { |u| u.available_name.presence || u.email }
      .join(', ').presence || '—'
  end

  # Returns the set of users that should see this notification, used by
  # the ActionCableListener to enumerate pubsub_tokens for an immediate
  # push. NOT used by the read path — that one re-checks per request via
  # `.visible_for`.
  def target_users
    base = User.joins(:account_users)
    base = base.where(account_users: { account_id: account_ids }) if scope_accounts?

    case audience_type
    when 'agents', 'managers', 'administrators'
      base.where(account_users: { role: AccountUser.roles[ROLE_AUDIENCE_TO_ACCOUNT_USER_ROLE.fetch(audience_type)] })
    when 'specific_users'
      base.where(id: audience_user_ids)
    else
      base
    end.distinct
  end

  private

  def broadcast_if_immediate
    return unless trigger_immediate?

    Rails.configuration.dispatcher.dispatch(
      OPERATIONS_NOTIFICATION_CREATED,
      Time.zone.now,
      operations_notification: self
    )
  end

  def account_ids_required_when_scoped_to_accounts
    return unless scope_accounts?
    return if account_ids.present?

    errors.add(:account_ids, 'must include at least one account when scope is "accounts"')
  end

  def audience_user_ids_required_when_specific_users
    return unless audience_specific_users?
    return if audience_user_ids.present?

    errors.add(:audience_user_ids, 'must include at least one user when audience is "specific users"')
  end

  # "Specific users" only makes sense when the operator already chose
  # which accounts to target — without that, the user picker would have
  # nothing meaningful to scope its choices by.
  def specific_users_require_account_scope
    return unless audience_specific_users?
    return if scope_accounts? && account_ids.present?

    errors.add(:audience_type, 'requires choosing one or more accounts before picking specific users')
  end
end
