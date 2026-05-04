class Api::V1::Accounts::LossReasonsController < Api::V1::Accounts::BaseController
  before_action :fetch_loss_reason, except: [:index, :create]
  before_action :check_authorization

  def index
    @loss_reasons = LossReason.ordered
  end

  def show; end

  def create
    @loss_reason = LossReason.create!(permitted_params)
  end

  def update
    @loss_reason.update!(permitted_params)
  end

  private

  def fetch_loss_reason
    @loss_reason = LossReason.find(params[:id])
  end

  def permitted_params
    params.require(:loss_reason).permit(:name, :position, :active)
  end
end
