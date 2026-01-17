# frozen_string_literal: true

class Api::V1::Accounts::Kanban::BoardStepsController < Api::V1::Accounts::Kanban::BaseController
  before_action :set_board
  before_action :set_step, only: [:show, :update, :destroy]
  before_action :ensure_actor_present!, only: [:create, :update, :destroy]

  def index
    authorize(@board, :show?)
    @steps = @board.ordered_steps
    @filtered_counts = calculate_filtered_counts if filter_params_present?
  end

  def show
    authorize @step
  end

  def create
    @step = @board.steps.new(step_params)
    authorize @step

    @step.save!
    render :show, status: :created
  rescue ActiveRecord::RecordInvalid
    render_unprocessable_entity(@step)
  end

  def update
    authorize @step

    @step.update!(step_params)
    render :show
  rescue ActiveRecord::RecordInvalid
    render_unprocessable_entity(@step)
  end

  def destroy
    authorize @step

    if @board.steps.count <= 1
      render json: { error: I18n.t('kanban.board_steps.errors.cannot_delete_last_step') }, status: :unprocessable_entity
      return
    end

    ActiveRecord::Base.transaction do
      move_tasks_to_adjacent_step
      @step.destroy!
    end
    head :no_content
  end

  private

  def move_tasks_to_adjacent_step
    return if @step.tasks.empty?

    target_step = find_target_step_for_tasks
    @step.tasks.update_all(board_step_id: target_step.id) # rubocop:disable Rails/SkipsModelValidations
    FazerAi::Kanban::BoardStep.reset_counters(target_step.id, :tasks)
    @step.association(:tasks).reload
  end

  def find_target_step_for_tasks
    ordered_ids = @board.steps_order
    current_index = ordered_ids.index(@step.id)
    target_index = current_index.zero? ? 1 : current_index - 1
    @board.steps.find(ordered_ids[target_index])
  end

  def set_board
    @board = policy_scope(FazerAi::Kanban::Board).find(params[:board_id])
  end

  def set_step
    @step = policy_scope(FazerAi::Kanban::BoardStep).find(params[:id])
  end

  def step_params
    params.require(:step).permit(
      :name,
      :description,
      :color,
      :cancelled
    )
  end

  def filter_params_present?
    params[:agent_id].present? || params[:inbox_id].present?
  end

  def calculate_filtered_counts
    counts = {}

    @steps.each do |step|
      scope = step.tasks
      scope = scope.joins(:task_agents).where(kanban_task_agents: { agent_id: params[:agent_id] }) if params[:agent_id].present?
      scope = scope.joins(conversations: :inbox).where(inboxes: { id: params[:inbox_id] }) if params[:inbox_id].present?

      counts[step.id] = scope.distinct.count
    end

    counts
  end
end
