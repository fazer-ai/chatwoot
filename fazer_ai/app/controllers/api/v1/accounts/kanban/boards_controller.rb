# frozen_string_literal: true

class Api::V1::Accounts::Kanban::BoardsController < Api::V1::Accounts::Kanban::BaseController
  ALLOWED_SORT_COLUMNS = %w[name updated_at created_at].freeze

  before_action :set_board, only: [:show, :update, :destroy, :update_agents, :update_inboxes, :toggle_favorite]

  def index
    authorize(FazerAi::Kanban::Board)
    @boards = policy_scope(FazerAi::Kanban::Board)
              .includes(
                :inboxes,
                :steps,
                assigned_agents: [:account_users, { avatar_attachment: :blob }]
              )

    @preference = Current.account_user.kanban_preference || Current.account_user.build_kanban_preference
    sort_by, order_by = resolve_sorting

    @boards = @boards.order(sort_by => order_by)
  end

  def show
    authorize @board
  end

  def toggle_favorite
    authorize @board

    @preference = Current.account_user.kanban_preference || Current.account_user.build_kanban_preference
    favorites = @preference.preferences['favorite_board_ids'] || []

    if favorites.include?(@board.id)
      favorites.delete(@board.id)
    else
      favorites.push(@board.id)
    end

    @preference.preferences['favorite_board_ids'] = favorites
    @preference.save!

    render json: { favorite_board_ids: favorites }
  end

  def create
    ensure_actor_present!
    @board = Current.account.kanban_boards.new(board_params_without_cancelled)
    authorize @board

    ActiveRecord::Base.transaction do
      @board.save!
      apply_cancelled_steps
      sync_inboxes(@board)
    end

    render :show, status: :created
  rescue ActiveRecord::RecordInvalid
    render_unprocessable_entity(@board)
  end

  def update
    ensure_actor_present!
    authorize @board

    ActiveRecord::Base.transaction do
      @board.update!(board_params)
      sync_inboxes(@board)
    end

    render :show
  rescue ActiveRecord::RecordInvalid
    render_unprocessable_entity(@board)
  end

  def destroy
    ensure_actor_present!
    authorize @board

    @board.destroy!
    head :no_content
  end

  def update_agents
    ensure_actor_present!
    authorize @board

    agent_ids = params[:agent_ids] || []
    valid_agent_ids = Current.account.users.where(id: agent_ids).pluck(:id)

    ActiveRecord::Base.transaction do
      @board.board_agents.where.not(agent_id: valid_agent_ids).destroy_all

      existing_agent_ids = @board.board_agents.pluck(:agent_id)
      new_agent_ids = valid_agent_ids - existing_agent_ids

      new_agent_ids.each do |agent_id|
        @board.board_agents.create!(agent_id: agent_id)
      end

      @board.touch # rubocop:disable Rails/SkipsModelValidations
    end

    @board.reload
    render :show
  end

  def update_inboxes
    ensure_actor_present!
    authorize @board

    inbox_ids = params[:inbox_ids] || []
    valid_inbox_ids = Current.account.inboxes.where(id: inbox_ids).pluck(:id)

    ActiveRecord::Base.transaction do
      @board.board_inboxes.where.not(inbox_id: valid_inbox_ids).destroy_all

      existing_inbox_ids = @board.board_inboxes.pluck(:inbox_id)
      new_inbox_ids = valid_inbox_ids - existing_inbox_ids

      new_inbox_ids.each do |inbox_id|
        @board.board_inboxes.create!(inbox_id: inbox_id)
      end

      @board.touch # rubocop:disable Rails/SkipsModelValidations
    end

    @board.reload
    render :show
  end

  private

  def set_board
    @board = policy_scope(FazerAi::Kanban::Board)
             .includes(
               :inboxes,
               :steps,
               assigned_agents: [:account_users, { avatar_attachment: :blob }]
             )
             .find(params[:id])
  end

  def board_params
    params.require(:board).permit(
      :name,
      :description,
      settings: {},
      steps_order: [],
      steps_attributes: [
        :name, :description, :color, :cancelled,
        { tasks_attributes: [:title, :description, :priority, :due_date] }
      ]
    )
  end

  def board_params_without_cancelled
    permitted = board_params
    if permitted[:steps_attributes].present?
      permitted[:steps_attributes] = permitted[:steps_attributes].map do |step_attrs|
        step_attrs.except(:cancelled)
      end
    end
    permitted
  end

  def apply_cancelled_steps # rubocop:disable Metrics/CyclomaticComplexity
    steps_attrs = params.dig(:board, :steps_attributes)
    return if steps_attrs.blank?

    ordered_steps = @board.ordered_steps
    last_index = ordered_steps.size - 1

    steps_attrs.each_with_index do |step_attrs, index|
      next unless step_attrs[:cancelled] == true || step_attrs[:cancelled] == 'true'
      # Skip first/last positions - BoardStep validation prevents cancelled on these
      next if index.zero? || index == last_index

      ordered_steps[index]&.update!(cancelled: true)
    end
  end

  def sync_inboxes(board)
    return unless params.dig(:board, :inbox_ids)

    inbox_ids = Current.account.inboxes.where(id: inbox_ids_param).pluck(:id)
    board.inbox_ids = inbox_ids
  end

  def inbox_ids_param
    Array(params.dig(:board, :inbox_ids)).map(&:to_i).uniq
  end

  def resolve_sorting
    sort_by = params[:sort]
    order_by = params[:order]

    if sort_by.present? && ALLOWED_SORT_COLUMNS.include?(sort_by)
      order_by = %w[asc desc].include?(order_by) ? order_by : 'asc'

      @preference.preferences['board_sorting'] = { sort: sort_by, order: order_by }
      @preference.save!

      return [sort_by, order_by]
    end

    defaults = FazerAi::Kanban::AccountUserPreference::DEFAULT_PREFERENCES['board_sorting']
    saved_pref = @preference.preferences['board_sorting'] || defaults
    [saved_pref['sort'], saved_pref['order']]
  end
end
