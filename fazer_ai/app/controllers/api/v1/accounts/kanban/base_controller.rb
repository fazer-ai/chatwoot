# frozen_string_literal: true

class Api::V1::Accounts::Kanban::BaseController < Api::V1::Accounts::BaseController
  before_action :ensure_kanban_feature_enabled

  private

  def ensure_kanban_feature_enabled
    return if Current.account&.kanban_feature_enabled?

    head :not_found
  end

  def current_actor
    Current.user
  end

  def ensure_actor_present!
    return if current_actor

    render json: { errors: ['User context missing'] }, status: :forbidden
  end

  def render_unprocessable_entity(record)
    render json: { errors: record.errors.full_messages }, status: :unprocessable_entity
  end
end
