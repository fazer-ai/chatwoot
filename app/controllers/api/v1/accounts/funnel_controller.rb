class Api::V1::Accounts::FunnelController < Api::V1::Accounts::BaseController
  before_action :authorize_funnel

  def show
    @stages = FunnelStage.active.ordered
    @conversations_by_stage = group_conversations(filtered_conversations)
  end

  def move
    service = Funnel::MoveConversationService.new(
      account: Current.account,
      conversation_display_id: params.require(:conversation_id),
      target_stage_name: params.require(:stage),
      user: Current.user,
      reason: params[:reason],
      source: params[:source] || 'web'
    )
    @result = service.perform
    render :show_move
  end

  def history
    conversation = Current.account.conversations.find_by!(display_id: params.require(:conversation_id))
    @history = Current.account.funnel_stage_changes
                      .where(conversation_id: conversation.id)
                      .order(created_at: :desc)
                      .limit(200)
  end

  def conversation_status
    conversation = Current.account.conversations.find_by!(display_id: params.require(:conversation_id))
    @conversation = conversation
    @stage = conversation.funnel_stage
  end

  private

  def authorize_funnel
    authorize :funnel, :"#{action_name}?"
  end

  def filtered_conversations
    relation = scoped_conversations
    relation = relation.where('conversations.created_at >= ?', from_date) if from_date.present?
    relation = relation.where('conversations.created_at <= ?', to_date) if to_date.present?
    relation = relation.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    relation = relation.where.not(funnel_stage_id: closed_stage_ids) if hide_closed?
    relation
  end

  def scoped_conversations
    Current.account.conversations
           .includes(:contact, :inbox)
           .where(funnel_stage_id: active_stage_ids)
  end

  def active_stage_ids
    @active_stage_ids ||= FunnelStage.active.pluck(:id)
  end

  def closed_stage_ids
    @closed_stage_ids ||= FunnelStage.active.closed_stages.pluck(:id)
  end

  def group_conversations(conversations)
    grouped = Hash.new { |h, k| h[k] = [] }
    conversations.find_each { |c| grouped[c.funnel_stage_id] << c }
    grouped
  end

  def from_date
    @from_date ||= parse_time(params[:from])
  end

  def to_date
    @to_date ||= parse_time(params[:to])
  end

  def parse_time(value)
    return if value.blank?

    Time.zone.parse(value)
  rescue ArgumentError
    nil
  end

  def hide_closed?
    ActiveModel::Type::Boolean.new.cast(params[:hide_closed])
  end
end
