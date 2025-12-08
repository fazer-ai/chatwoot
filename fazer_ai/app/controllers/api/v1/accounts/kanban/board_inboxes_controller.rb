# frozen_string_literal: true

class Api::V1::Accounts::Kanban::BoardInboxesController < Api::V1::Accounts::Kanban::BaseController
  before_action :set_board
  before_action :set_board_inbox, only: [:destroy]
  before_action :ensure_actor_present!, only: [:create, :destroy]

  def index
    authorize(FazerAi::Kanban::BoardInbox)
    @board_inboxes = scoped_inboxes
  end

  def create
    @board_inbox = @board.board_inboxes.new(board_inbox_params)
    authorize @board_inbox

    @board_inbox.save!
    render :show, status: :created
  rescue ActiveRecord::RecordInvalid
    render_unprocessable_entity(@board_inbox)
  end

  def destroy
    authorize @board_inbox

    @board_inbox.destroy!
    head :no_content
  end

  private

  def set_board
    @board = policy_scope(FazerAi::Kanban::Board).find(params[:board_id])
  end

  def set_board_inbox
    @board_inbox = scoped_inboxes.find(params[:id])
  end

  def scoped_inboxes
    policy_scope(FazerAi::Kanban::BoardInbox)
      .where(board: @board)
      .includes(:inbox)
  end

  def board_inbox_params
    params.require(:board_inbox).permit(:inbox_id)
  end
end
