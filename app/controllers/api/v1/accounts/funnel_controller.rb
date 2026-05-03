class Api::V1::Accounts::FunnelController < Api::V1::Accounts::BaseController
  before_action :authorize_funnel

  def show
    @stages = Current.account.funnel_stages.active.ordered
    @stages_by_name = @stages.index_by(&:name)
    @labels_by_title = Current.account.labels.where(title: @stages.map(&:name)).index_by(&:title)
    @conversations_by_stage = group_conversations_by_stage(filtered_conversations)
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

  private

  def authorize_funnel
    authorize :funnel, :"#{action_name}?"
  end

  def filtered_conversations
    relation = scoped_conversations
    relation = relation.where('conversations.created_at >= ?', from_date) if from_date.present?
    relation = relation.where('conversations.created_at <= ?', to_date) if to_date.present?
    relation = relation.where(inbox_id: params[:inbox_id]) if params[:inbox_id].present?
    relation
  end

  def scoped_conversations
    Current.account.conversations
           .includes(:contact, :inbox)
           .where('cached_label_list ILIKE ANY (ARRAY[?])', stage_label_patterns)
  end

  def stage_label_patterns
    Current.account.funnel_stages.active.pluck(:name).map { |n| "%#{n}%" }
  end

  def group_conversations_by_stage(conversations)
    closed_stage_names = @stages.select(&:closed).map(&:name)
    grouped = Hash.new { |h, k| h[k] = [] }

    conversations.find_each do |conversation|
      stage = pick_stage_for_conversation(conversation, closed_stage_names)
      next unless stage

      grouped[stage.name] << conversation
    end

    grouped
  end

  def pick_stage_for_conversation(conversation, closed_stage_names)
    label_titles = Array(conversation.label_list)
    matching_stages = label_titles.filter_map { |title| @stages_by_name[title] }
    return nil if matching_stages.empty?

    return nil if hide_closed? && matching_stages.map(&:name).intersect?(closed_stage_names)

    matching_stages.max_by(&:position)
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
