class Api::V1::Accounts::Inboxes::AgentBotObserversController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  before_action -> { authorize @inbox, :set_agent_bot? }
  before_action :fetch_agent_bot, only: [:create, :destroy]

  def index
    @agent_bots = @inbox.observer_agent_bots
  end

  # Idempotent: adding a bot that already observes the inbox answers with it, the way set_agent_bot
  # reuses the responder's row.
  def create
    @inbox.agent_bot_observers.find_or_create_by!(agent_bot: @agent_bot)
  end

  def destroy
    @inbox.agent_bot_observers.find_by!(agent_bot: @agent_bot).destroy!
    head :ok
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:inbox_id])
  end

  def fetch_agent_bot
    @agent_bot = AgentBot.accessible_to(Current.account).find(params[:id] || params[:agent_bot])
  end
end
