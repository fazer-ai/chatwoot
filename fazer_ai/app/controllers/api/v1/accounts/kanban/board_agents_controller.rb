# frozen_string_literal: true

class Api::V1::Accounts::Kanban::BoardAgentsController < Api::V1::Accounts::Kanban::BaseController
  before_action :set_board
  before_action :set_agent, only: [:update, :destroy]
  before_action :ensure_actor_present!, only: [:create, :update, :destroy]

  def index
    authorize(FazerAi::Kanban::BoardAgent)
    @agents = scoped_agents
  end

  def create
    @agent = @board.board_agents.new(agent_params)
    authorize @agent

    @agent.save!
    render :show, status: :created
  rescue ActiveRecord::RecordInvalid
    render_unprocessable_entity(@agent)
  end

  def update
    authorize @agent

    @agent.update!(agent_params)
    render :show
  rescue ActiveRecord::RecordInvalid
    render_unprocessable_entity(@agent)
  end

  def destroy
    authorize @agent

    @agent.destroy!
    head :no_content
  end

  private

  def set_board
    @board = policy_scope(FazerAi::Kanban::Board).find(params[:board_id])
  end

  def set_agent
    @agent = policy_scope(FazerAi::Kanban::BoardAgent)
             .includes(:agent)
             .find(params[:id])
    return if @agent.board_id == @board.id

    head :not_found
    return
  end

  def scoped_agents
    policy_scope(FazerAi::Kanban::BoardAgent)
      .where(board: @board)
      .includes(:agent)
  end

  def agent_params
    params.require(:agent).permit(:agent_id)
  end
end
