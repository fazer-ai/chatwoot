class Api::V1::Accounts::TabulationSubcategoriesController < Api::V1::Accounts::BaseController
  before_action :fetch_category
  before_action :fetch_subcategory, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @tabulation_subcategories = @category.tabulation_subcategories
  end

  def show; end

  def create
    @tabulation_subcategory = @category.tabulation_subcategories.create!(subcategory_params)
  end

  def update
    @tabulation_subcategory.update!(subcategory_params)
  end

  def destroy
    @tabulation_subcategory.destroy!
    head :ok
  end

  private

  def fetch_category
    @category = Current.account.tabulation_categories.find(params[:tabulation_category_id])
  end

  def fetch_subcategory
    @tabulation_subcategory = @category.tabulation_subcategories.find(params[:id])
  end

  def subcategory_params
    params.require(:tabulation_subcategory).permit(:name, :active)
  end

  def check_authorization
    authorize(@tabulation_subcategory || TabulationSubcategory)
  end
end
