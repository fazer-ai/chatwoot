# frozen_string_literal: true

class Api::V1::Accounts::Kanban::AuditEventsController < Api::V1::Accounts::Kanban::BaseController
  before_action :set_task
  before_action :set_audit_event, only: [:show]

  def index
    authorize(FazerAi::Kanban::AuditEvent)
    @audit_events = scoped_events
  end

  def show
    authorize @audit_event
  end

  private

  def set_task
    @task = policy_scope(FazerAi::Kanban::Task).find(params[:task_id])
  end

  def set_audit_event
    @audit_event = scoped_events.find(params[:id])
  end

  def scoped_events
    policy_scope(FazerAi::Kanban::AuditEvent)
      .where(task: @task)
      .includes(:actor)
      .order(created_at: :desc)
  end
end
