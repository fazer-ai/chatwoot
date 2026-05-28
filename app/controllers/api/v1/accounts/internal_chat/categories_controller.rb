class Api::V1::Accounts::InternalChat::CategoriesController < Api::V1::Accounts::InternalChat::BaseController
  before_action :fetch_category, only: [:update, :destroy]

  def index
    authorize InternalChat::Category, :index?
    @categories = Current.account.internal_chat_categories.ordered.includes(:channels)
    render json: @categories.map { |category| category_response(category) }
  end

  def create
    authorize InternalChat::Category, :create?
    @category = Current.account.internal_chat_categories.create!(category_params)
    render json: category_response(@category), status: :created
  end

  def update
    authorize @category, :update?
    @category.update!(category_params)
    render json: category_response(@category)
  end

  def destroy
    authorize @category, :destroy?
    @category.destroy!
    head :ok
  end

  private

  def fetch_category
    @category = Current.account.internal_chat_categories.find(params[:id])
  end

  def category_params
    params.require(:category).permit(:name, :position)
  end

  def category_response(category)
    {
      id: category.id,
      name: category.name,
      position: category.position,
      account_id: category.account_id,
      channels_count: category.channels.size,
      created_at: category.created_at,
      updated_at: category.updated_at
    }
  end
end
