module SuperAdmin::FeaturesHelper
  def self.available_features
    YAML.load(ERB.new(Rails.root.join('app/helpers/super_admin/features.yml').read).result).with_indifferent_access
  end

  def self.plan_details
    plan = ChatwootHub.pricing_plan
    quantity = ChatwootHub.pricing_plan_quantity

    if plan == 'premium'
      "You are currently on the <span class='font-semibold'>#{plan}</span> plan with <span class='font-semibold'>#{quantity} agents</span>."
    else
      "You are currently on the <span class='font-semibold'>#{plan}</span> edition plan."
    end
  end

  def self.fazer_ai_subscription_details
    parts = [subscription_status_label, subscription_features_text]
    parts << kanban_accounts_text if FazerAiHub.subscription_active?
    parts.join(' · ')
  end

  def self.subscription_status_label
    status = FazerAiHub.subscription_status
    label = case status
            when 'active' then "<span class='text-green-600 font-semibold'>Active</span>"
            when 'past_due' then "<span class='text-yellow-600 font-semibold'>Past Due</span>"
            when 'trialing' then "<span class='text-blue-600 font-semibold'>Trialing</span>"
            else "<span class='text-slate-500 font-semibold'>Inactive</span>"
            end
    result = "Status: #{label}"
    result += " · #{subscription_canceling_text}" if FazerAiHub.subscription_canceling?
    result
  end

  def self.subscription_features_text
    features = FazerAiHub.enabled_features
    features_text = features.any? ? features.map(&:titleize).join(', ') : 'None'
    "Features: <span class='font-semibold'>#{features_text}</span>"
  end

  def self.kanban_accounts_text
    kanban_limit = FazerAiHub.kanban_account_limit
    current_count = Account.where('feature_flags & ? > 0', Featurable.feature_flag_value('kanban')).count
    limit_display = kanban_limit.zero? ? '∞' : kanban_limit
    "Kanban Accounts: <span class='font-semibold'>#{current_count}/#{limit_display}</span>"
  end

  def self.subscription_canceling_text
    period_end = FazerAiHub.subscription_period_end
    return nil if period_end.blank?

    formatted_date = Time.zone.at(period_end).strftime('%B %d, %Y')
    "<span class='text-yellow-600 font-semibold'>Cancels on #{formatted_date}</span>"
  end
end
