# frozen_string_literal: true

class Api::V1::Accounts::Kanban::TasksController < Api::V1::Accounts::Kanban::BaseController # rubocop:disable Metrics/ClassLength
  ALLOWED_SORT_COLUMNS = %w[title updated_at created_at priority due_date].freeze
  DEFAULT_PER_PAGE = 25
  MAX_PER_PAGE = 100

  before_action :set_task, only: [:show, :update, :destroy, :move]
  before_action :ensure_actor_present!, only: [:create, :update, :destroy, :move]

  def index
    authorize(FazerAi::Kanban::Task)
    @tasks = paginated_tasks
  end

  def show
    authorize @task
  end

  def create # rubocop:disable Metrics/AbcSize
    @task = Current.account.kanban_tasks.new(task_create_params.except(:labels))
    authorize @task

    ActiveRecord::Base.transaction do
      @task.board_step ||= @task.board.ordered_steps.first
      @task.creator = current_actor
      @task.insert_before_task_id = params[:insert_before_task_id]
      @task.save!
      update_task_labels if task_create_params[:labels].present?
      @task.reorder_for_user!(current_actor)
    end

    @task = reload_task_with_associations(@task.id)
    enqueue_audit_event(@task, 'task.created')
    render :show, status: :created
  rescue ActiveRecord::RecordInvalid
    render_unprocessable_entity(@task)
  end

  def update
    authorize @task

    ActiveRecord::Base.transaction do
      @task.update!(task_params.except(:labels))
      update_task_labels if params[:task].key?(:labels)
    end

    changes = @task.previous_changes.except('updated_at')
    @task = reload_task_with_associations(@task.id)
    metadata = { changes: changes }
    enqueue_audit_event(@task, 'task.updated', metadata: metadata)
    render :show
  rescue ActiveRecord::RecordInvalid
    render_unprocessable_entity(@task)
  end

  def move # rubocop:disable Metrics/AbcSize
    authorize @task, :update?

    target_step_id = params[:board_step_id]
    insert_before_task_id = params[:insert_before_task_id]
    preference = current_kanban_preference

    @task.insert_before_task_id = insert_before_task_id
    if target_step_id.blank? || target_step_id.to_i == @task.board_step_id
      @task.reorder_for_user!(current_actor, preference: preference)
      # Dispatch event for within-step reorder (no update! was called, so no after_commit)
      dispatch_task_reorder_event(@task)
    else
      old_step_id = @task.board_step_id
      @task.update!(board_step_id: target_step_id)

      @task.reorder_for_user!(current_actor, preference: preference)

      if preference
        old_order = preference.tasks_order_for(old_step_id).dup
        preference.update_tasks_order!(old_step_id, old_order) if old_order.delete(@task.id)
      end
    end

    @task = reload_task_with_associations(@task.id)
    render :show
  end

  def destroy
    authorize @task

    @task.destroy!
    head :no_content
  end

  private

  def dispatch_task_reorder_event(task)
    Rails.configuration.dispatcher.dispatch(Events::Types::KANBAN_TASK_UPDATED, Time.zone.now, task: task, changed_attributes: {})
  end

  def current_kanban_preference
    @current_kanban_preference ||= begin
      account_user = current_actor.account_users.find_by(account_id: Current.account.id)
      account_user.kanban_preference || account_user.build_kanban_preference
    end
  end

  def paginated_tasks
    scope = initial_task_scope
    scope = apply_filters(scope)
    scope = apply_sorting(scope)

    page = [params[:page].to_i, 1].max
    per_page_param = params[:per_page].to_i
    per_page = per_page_param.positive? ? [per_page_param, MAX_PER_PAGE].min : DEFAULT_PER_PAGE
    offset = (page - 1) * per_page

    @total_count = scope.count
    @page = page
    @per_page = per_page
    @has_more = offset + per_page < @total_count

    scope.limit(per_page).offset(offset)
  end

  def initial_task_scope
    policy_scope(FazerAi::Kanban::Task)
      .ordered
      .includes(
        assigned_agents: [:account_users, { avatar_attachment: :blob }],
        creator: [:account_users, { avatar_attachment: :blob }],
        contacts: { avatar_attachment: :blob },
        conversations: [:inbox, { contact: { avatar_attachment: :blob } }],
        board: [
          :steps,
          { assigned_agents: [:account_users, { avatar_attachment: :blob }] }
        ]
      )
  end

  def apply_filters(scope) # rubocop:disable Metrics/AbcSize
    if params[:assigned_agent_ids].present?
      agent_ids = Array(params[:assigned_agent_ids]).map(&:to_i)
      scope = scope.joins(:task_agents).where(kanban_task_agents: { agent_id: agent_ids })
    end

    scope = scope.joins(:task_agents).where(kanban_task_agents: { agent_id: params[:agent_id] }) if params[:agent_id].present?
    scope = scope.joins(conversations: :inbox).where(inboxes: { id: params[:inbox_id] }) if params[:inbox_id].present?

    direct_filter_columns.each do |column|
      value = params[column]
      scope = scope.where(column => value) if value.present?
    end

    scope
  end

  def apply_sorting(scope)
    return sort_by_position(scope) if params[:sort].blank?

    sort_by = params[:sort]
    order_by = params[:order].to_sym

    save_sort_preference(sort_by, order_by) if params[:board_id].present?

    return scope unless ALLOWED_SORT_COLUMNS.include?(sort_by)

    if sort_by == 'priority'
      sort_by_priority(scope, order_by)
    else
      scope.reorder(sort_by => order_by)
    end
  end

  def sort_by_position(scope)
    return scope if params[:board_step_id].blank?

    step_id = params[:board_step_id].to_s
    tasks_order = current_kanban_preference.tasks_order_for(step_id)

    return scope if tasks_order.blank?

    position_sql = "COALESCE(array_position(ARRAY[#{tasks_order.join(',')}]::bigint[], kanban_tasks.id), #{tasks_order.length + 1})"
    scope.reorder(Arel.sql(position_sql) => :asc)
  end

  def save_sort_preference(sort_by, order_by)
    preference = current_kanban_preference
    preference.preferences['task_sorting'] ||= {}
    preference.preferences['task_sorting'][params[:board_id].to_s] = { 'sort' => sort_by, 'order' => order_by.to_s }
    preference.save!
  end

  def sort_by_priority(scope, order_by)
    priorities = FazerAi::Kanban::Task::PRIORITIES
    priority_order_sql = "COALESCE(array_position(ARRAY['#{priorities.join("','")}']::text[], priority), #{priorities.length + 1})"
    inverted_order = order_by == :desc ? :asc : :desc
    scope.reorder(Arel.sql(priority_order_sql) => inverted_order)
  end

  def set_task
    @task = reload_task_with_associations(params[:id])
  end

  def reload_task_with_associations(task_id)
    policy_scope(FazerAi::Kanban::Task)
      .includes(
        assigned_agents: [:account_users, { avatar_attachment: :blob }],
        creator: [:account_users, { avatar_attachment: :blob }],
        contacts: { avatar_attachment: :blob },
        conversations: [:inbox, { contact: { avatar_attachment: :blob } }],
        board: [
          :steps,
          { assigned_agents: [:account_users, { avatar_attachment: :blob }] }
        ]
      )
      .find(task_id)
  end

  def task_params
    params.require(:task).permit(
      :title,
      :description,
      :priority,
      :start_date,
      :due_date,
      :board_step_id,
      contact_ids: [],
      conversation_ids: [],
      assigned_agent_ids: [],
      labels: []
    ).merge(account: Current.account)
  end

  def task_create_params
    params.require(:task).permit(
      :title,
      :description,
      :priority,
      :start_date,
      :due_date,
      :board_id,
      :board_step_id,
      contact_ids: [],
      conversation_ids: [],
      assigned_agent_ids: [],
      labels: []
    ).merge(account: Current.account)
  end

  def update_task_labels
    labels = params[:task][:labels] || []
    @task.update_labels(labels)
  end

  def enqueue_audit_event(task, action, metadata: {})
    FazerAi::Kanban::AuditEventJob.perform_later(
      task_id: task.id,
      account_id: task.account_id,
      action: action,
      metadata: metadata,
      performed_by_id: current_actor&.id
    )
  end

  def filter_mappings
    %i[board_id board_step_id priority assigned_agent_ids]
  end

  def direct_filter_columns
    %i[board_id board_step_id priority]
  end
end
