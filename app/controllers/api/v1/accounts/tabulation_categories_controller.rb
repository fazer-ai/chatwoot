class Api::V1::Accounts::TabulationCategoriesController < Api::V1::Accounts::BaseController
  before_action :fetch_tabulation_category, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @tabulation_categories = Current.account.tabulation_categories
  end

  def show; end

  def create
    @tabulation_category = Current.account.tabulation_categories.create!(category_params)
  end

  def update
    @tabulation_category.update!(category_params)
  end

  def destroy
    @tabulation_category.destroy!
    head :ok
  end

  private

  def fetch_tabulation_category
    @tabulation_category = Current.account.tabulation_categories.find(params[:id])
  end

  def category_params
    params.require(:tabulation_category).permit(:name, :color, :active)
  end

  def check_authorization
    authorize(@tabulation_category || TabulationCategory)
  end
end
