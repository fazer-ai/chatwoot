class Api::V1::Accounts::FunnelStagesController < Api::V1::Accounts::BaseController
  before_action :fetch_funnel_stage, except: [:index, :create]
  before_action :check_authorization

  def index
    @funnel_stages = FunnelStage.ordered
  end

  def show; end

  def create
    @funnel_stage = FunnelStage.create!(permitted_params)
  end

  def update
    @funnel_stage.update!(permitted_params)
  end

  def destroy
    @funnel_stage.destroy!
    head :ok
  end

  private

  def fetch_funnel_stage
    @funnel_stage = FunnelStage.find(params[:id])
  end

  def permitted_params
    params.require(:funnel_stage).permit(:name, :description, :position, :closed, :active)
  end
end
