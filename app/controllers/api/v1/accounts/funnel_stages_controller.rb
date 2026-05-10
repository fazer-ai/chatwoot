# Funnel stages are operational invariants of the AurisChat installation —
# they're shared by every account and aren't editable by tenants. The Super
# Admin dashboard manages create/update/destroy. Account users can only read
# the catalog so they can render and move conversations between stages.
class Api::V1::Accounts::FunnelStagesController < Api::V1::Accounts::BaseController
  before_action :fetch_funnel_stage, only: [:show]
  before_action :check_authorization

  def index
    @funnel_stages = FunnelStage.ordered
  end

  def show; end

  private

  def fetch_funnel_stage
    @funnel_stage = FunnelStage.find(params[:id])
  end
end
