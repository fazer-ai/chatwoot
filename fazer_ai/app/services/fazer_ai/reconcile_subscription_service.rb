# frozen_string_literal: true

class FazerAi::ReconcileSubscriptionService
  def perform
    return unless ChatwootApp.fazer_ai?

    reconcile_feature_limits if FazerAiHub.subscription_active?
  end

  private

  def reconcile_feature_limits
    reconcile_kanban_limit
  end

  def reconcile_kanban_limit
    return unless FazerAiHub.feature_enabled?('kanban')

    limit = FazerAiHub.kanban_account_limit
    # nil means feature not available, 0 means unlimited — skip reconciliation in both cases
    return if limit.nil? || limit.zero?

    enabled_accounts = Account.where('feature_flags & ? != 0', Featurable.feature_flag_value('kanban'))
                              .order(id: :asc)
                              .pluck(:id)

    return if enabled_accounts.size <= limit

    accounts_to_disable = enabled_accounts.last(enabled_accounts.size - limit)
    Account.where(id: accounts_to_disable).find_each do |account|
      account.disable_features!('kanban')
    end
  end
end
