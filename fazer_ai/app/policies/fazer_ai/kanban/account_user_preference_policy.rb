# frozen_string_literal: true

class FazerAi::Kanban::AccountUserPreferencePolicy < FazerAi::Kanban::ApplicationPolicy
  def update?
    feature_enabled? && (admin? || agent?) && owns_preference?
  end

  private

  def owns_preference?
    return true if record.new_record?
    return false unless account_user

    record.account_user_id == account_user.id
  end
end
