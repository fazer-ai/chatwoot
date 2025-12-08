# frozen_string_literal: true

class FazerAi::Kanban::TaskPolicy < FazerAi::Kanban::ApplicationPolicy
  def index?
    feature_enabled? && (admin? || agent?)
  end

  def create?
    return false unless feature_enabled?
    return true if admin?

    board = target_board
    board.present? && agent_can_manage_board?(board)
  end

  def update?
    feature_enabled? && (admin? || agent_can_modify_record?)
  end

  def destroy?
    update?
  end

  def move?
    update?
  end

  def reorder?
    update?
  end

  def attach_contact?
    update?
  end

  def detach_contact?
    update?
  end

  def attach_conversation?
    update?
  end

  def detach_conversation?
    update?
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      base_policy.send(:task_scope_for, scope)
    end

    private

    def base_policy
      @base_policy ||= FazerAi::Kanban::ApplicationPolicy.new(user_context, scope)
    end
  end

  private

  def agent_can_modify_record?
    record.respond_to?(:board) &&
      record.board.present? &&
      agent_can_manage_board?(record.board)
  end

  def target_board
    return unless record.respond_to?(:board) || record.respond_to?(:board_id)

    record.board || fetch_board
  end

  def fetch_board
    return unless record.respond_to?(:board_id)

    FazerAi::Kanban::Board.find_by(id: record.board_id)
  end
end
