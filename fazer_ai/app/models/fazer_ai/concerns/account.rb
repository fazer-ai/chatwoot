# frozen_string_literal: true

module FazerAi::Concerns::Account
  extend ActiveSupport::Concern

  included do
    has_many :kanban_boards,
             class_name: 'FazerAi::Kanban::Board',
             dependent: :destroy_async,
             inverse_of: :account
    has_many :kanban_tasks,
             class_name: 'FazerAi::Kanban::Task',
             dependent: :destroy_async,
             inverse_of: :account

    validate :fazer_ai_feature_limit_not_exceeded
    after_commit :sync_fazer_ai_feature_usage, if: :kanban_feature_changed?
  end

  def kanban_feature_enabled?
    feature_enabled?('kanban') && kanban_subscription_feature_accessible?
  end

  def kanban_subscription_feature_accessible?
    FazerAiHub.subscription_active? &&
      FazerAiHub.feature_enabled?('kanban') &&
      !FazerAiHub.kanban_account_limit.nil?
  end

  def fazer_ai_subscription_feature_accessible?(subscription_feature_name)
    FazerAiHub.subscription_active? && FazerAiHub.feature_enabled?(subscription_feature_name)
  end

  def self.fazer_ai_feature?(feature_name)
    feature = Featurable::FEATURE_LIST.find { |f| f['name'] == feature_name }
    feature&.dig('fazer_ai') == true
  end

  private

  def fazer_ai_feature_limit_not_exceeded
    return unless feature_flags_changed?

    fazer_ai_features_being_enabled = Featurable::FEATURE_LIST.select do |feature|
      feature['fazer_ai'] && enabling_feature?(feature['name'])
    end
    return if fazer_ai_features_being_enabled.empty?

    sync_and_validate_kanban_limit if enabling_feature?('kanban')
  end

  def sync_and_validate_kanban_limit
    Internal::CheckNewVersionsJob.perform_now
    validate_kanban_limit
  end

  def enabling_feature?(feature_name)
    return false unless respond_to?("feature_#{feature_name}_changed?")

    send("feature_#{feature_name}_changed?") && send("feature_#{feature_name}?")
  end

  def validate_kanban_limit
    return unless FazerAiHub.feature_enabled?('kanban')

    limit = FazerAiHub.kanban_account_limit
    if limit.nil?
      errors.add(:base, I18n.t('errors.fazer_ai.kanban_feature_not_available'))
      return
    end

    # 0 means unlimited, skip enforcement
    return if limit.zero?

    current_count = Account.where('feature_flags & ? != 0', Featurable.feature_flag_value('kanban')).where.not(id: id).count
    return if current_count < limit

    errors.add(:base, I18n.t('errors.fazer_ai.kanban_account_limit_reached', limit: limit))
  end

  def kanban_feature_changed?
    return false unless previous_changes.key?('feature_flags')

    old_flags, new_flags = previous_changes['feature_flags']
    kanban_flag = Featurable.feature_flag_value('kanban')
    old_kanban = old_flags.to_i.anybits?(kanban_flag)
    new_kanban = new_flags.to_i.anybits?(kanban_flag)
    old_kanban != new_kanban
  end

  def sync_fazer_ai_feature_usage
    Internal::CheckNewVersionsJob.perform_later
  end
end
