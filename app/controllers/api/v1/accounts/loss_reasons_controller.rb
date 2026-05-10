# Loss reasons live alongside funnel stages and are managed exclusively from
# the Super Admin dashboard. Account-scoped endpoints stay read-only so the
# Funnel UI can list them and `Funnel::MoveConversationService` can resolve a
# reason by id when an agent moves a conversation into a "lost" stage.
class Api::V1::Accounts::LossReasonsController < Api::V1::Accounts::BaseController
  before_action :fetch_loss_reason, only: [:show]
  before_action :check_authorization

  def index
    @loss_reasons = LossReason.ordered
  end

  def show; end

  private

  def fetch_loss_reason
    @loss_reason = LossReason.find(params[:id])
  end
end
