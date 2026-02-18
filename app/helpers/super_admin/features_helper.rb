module SuperAdmin::FeaturesHelper # rubocop:disable Metrics/ModuleLength
  def self.all_features
    YAML.load(ERB.new(Rails.root.join('app/helpers/super_admin/features.yml').read).result).with_indifferent_access
  end

  def self.available_features
    all_features.reject { |_, attrs| attrs[:fazer_ai] }
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
    result = parts.compact.join(' · ')
    result += "<br>#{sync_warning_text}" if FazerAiHub.out_of_sync?
    result.html_safe # rubocop:disable Rails/OutputSafety
  end

  def self.subscription_status_label
    status = FazerAiHub.subscription_status
    label = case status
            when 'active' then "<span class='text-green-600 font-semibold'>Active</span>"
            when 'past_due' then "<span class='text-yellow-600 font-semibold'>Past Due</span>"
            when 'trialing' then "<span class='text-blue-600 font-semibold'>Trialing</span>"
            else
              if FazerAiHub.never_synced?
                "<span class='text-slate-500 font-semibold'>Never Synced</span>"
              else
                "<span class='text-slate-500 font-semibold'>Inactive</span>"
              end
            end
    result = "Status: #{label}"
    result += " · #{subscription_trialing_text}" if status == 'trialing'
    result += " · #{subscription_canceling_text}" if FazerAiHub.subscription_canceling?
    result
  end

  def self.sync_warning_text
    last_synced = FazerAiHub.last_synced_at
    warning_badge = "<span class='text-yellow-600 font-semibold'>⚠️ Out of sync</span>"
    support_link = "<a href='mailto:support@fazer.ai' class='text-blue-600 underline'>support@fazer.ai</a>"

    message = if last_synced.present?
                days = ((Time.current - last_synced) / 1.day).ceil
                "#{warning_badge} (last synced #{days} #{'day'.pluralize(days)} ago)"
              else
                warning_badge
              end

    "#{message} — contact support at #{support_link}"
  end

  def self.subscription_trialing_text
    period_end = FazerAiHub.subscription_period_end
    return nil if period_end.blank?

    end_date = Time.zone.at(period_end)
    days_remaining = ((end_date - Time.current) / 1.day).ceil

    if days_remaining <= 0
      "<span class='text-red-600 font-semibold'>Trial ends today</span>"
    elsif days_remaining <= 3
      "<span class='text-yellow-600 font-semibold'>#{days_remaining} #{'day'.pluralize(days_remaining)} remaining</span>"
    else
      formatted_date = end_date.strftime('%B %d, %Y')
      "<span class='text-blue-600'>Ends #{formatted_date}</span>"
    end
  end

  def self.subscription_features_text
    features = FazerAiHub.enabled_features
    features_text = features.any? ? features.map(&:titleize).join(', ') : 'None'
    "Features: <span class='font-semibold'>#{features_text}</span>"
  end

  def self.kanban_accounts_text
    kanban_limit = FazerAiHub.kanban_account_limit
    current_count = Account.where('feature_flags & ? != 0', Featurable.feature_flag_value('kanban')).count
    limit_display = if kanban_limit.nil?
                      '-'
                    elsif kanban_limit.zero?
                      I18n.t('super_admin.settings.unlimited')
                    else
                      kanban_limit
                    end
    "Kanban Accounts: <span class='font-semibold'>#{current_count}/#{limit_display}</span>"
  end

  def self.subscription_canceling_text
    period_end = FazerAiHub.subscription_period_end
    return nil if period_end.blank?

    formatted_date = Time.zone.at(period_end).strftime('%B %d, %Y')
    "<span class='text-yellow-600 font-semibold'>Cancels on #{formatted_date}</span>"
  end

  def self.accounts_with_fazer_ai_features
    fazer_ai_features = FazerAiHub.enabled_features
    return [] if fazer_ai_features.empty?

    accounts_data = []
    fazer_ai_features.each do |feature|
      flag_value = Featurable.feature_flag_value(feature)
      next if flag_value.zero?

      Account.where('feature_flags & ? != 0', flag_value).find_each do |account|
        existing = accounts_data.find { |a| a[:id] == account.id }
        if existing
          existing[:features] << feature.titleize
        else
          accounts_data << { id: account.id, name: account.name, features: [feature.titleize] }
        end
      end
    end
    accounts_data.sort_by { |a| a[:name].downcase }
  end

  def self.fazer_ai_features
    all_features.select { |_, attrs| attrs[:fazer_ai] }
  end
end
