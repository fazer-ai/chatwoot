# frozen_string_literal: true

# == Schema Information
#
# Table name: kanban_tasks
#
#  id                  :bigint           not null, primary key
#  cached_label_list   :text
#  description         :text
#  due_date            :datetime
#  overdue_notified_at :datetime
#  priority            :string
#  start_date          :datetime
#  step_changed_at     :datetime
#  title               :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  board_id            :bigint           not null
#  board_step_id       :bigint           not null
#  created_by_id       :bigint
#
# Indexes
#
#  index_kanban_tasks_on_account_id                  (account_id)
#  index_kanban_tasks_on_account_id_and_created_at   (account_id,created_at)
#  index_kanban_tasks_on_board_id                    (board_id)
#  index_kanban_tasks_on_board_id_and_board_step_id  (board_id,board_step_id)
#  index_kanban_tasks_on_board_id_and_priority       (board_id,priority)
#  index_kanban_tasks_on_board_step_id               (board_step_id)
#  index_kanban_tasks_on_board_step_id_and_priority  (board_step_id,priority)
#  index_kanban_tasks_on_created_by_id               (created_by_id)
#  index_kanban_tasks_on_due_date                    (due_date)
#  index_kanban_tasks_on_priority                    (priority)
#  index_kanban_tasks_on_step_and_created_at         (board_step_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (board_id => kanban_boards.id)
#  fk_rails_...  (board_step_id => kanban_board_steps.id)
#  fk_rails_...  (created_by_id => users.id) ON DELETE => nullify
#
class FazerAi::Kanban::Task < ApplicationRecord # rubocop:disable Metrics/ClassLength
  include Labelable

  self.table_name = 'kanban_tasks'

  PRIORITIES = %w[urgent high medium low].freeze
  DESCRIPTION_MAX_LENGTH = 5000

  belongs_to :account
  belongs_to :board
  belongs_to :board_step, counter_cache: true
  belongs_to :creator,
             class_name: 'User',
             foreign_key: :created_by_id,
             inverse_of: :kanban_created_tasks,
             optional: true

  has_many :task_agents,
           class_name: 'FazerAi::Kanban::TaskAgent',
           dependent: :destroy,
           inverse_of: :task
  has_many :assigned_agents, through: :task_agents, source: :agent
  has_many :task_contacts,
           class_name: 'FazerAi::Kanban::TaskContact',
           dependent: :destroy,
           inverse_of: :task
  has_many :contacts, through: :task_contacts
  has_many :conversations,
           class_name: 'Conversation',
           foreign_key: :kanban_task_id,
           dependent: :nullify,
           inverse_of: :kanban_task
  has_many :audit_events,
           class_name: 'FazerAi::Kanban::AuditEvent',
           dependent: :destroy,
           inverse_of: :task

  attr_reader :insert_before_task_id

  def insert_before_task_id=(value)
    @insert_before_task_id = value
    @insert_before_task_id_set = true
  end

  def insert_before_task_id_set?
    @insert_before_task_id_set == true
  end

  def conversation_ids=(display_ids)
    resolved_account = account || Current.account
    @conversation_ids_to_assign = resolved_account.conversations.where(display_id: display_ids).pluck(:id)
  end

  def conversation_ids
    Conversation.where(kanban_task_id: id).pluck(:display_id)
  end

  def assigned_agent_ids=(ids)
    @assigned_agent_ids_to_sync = Array(ids).filter_map { |id| id.to_i if id.present? }
  end

  def assigned_agent_ids
    return @assigned_agent_ids_to_sync if @assigned_agent_ids_to_sync.present?

    task_agents.pluck(:agent_id)
  end

  validates :account, :board, :board_step, presence: true
  validates :title, presence: true, length: { maximum: 255 }
  validates :description, length: { maximum: DESCRIPTION_MAX_LENGTH }
  validates :priority, inclusion: { in: PRIORITIES }, allow_nil: true
  validate :scheduled_dates_are_coherent
  validate :assigned_agents_belong_to_board
  validate :contacts_belong_to_account
  validate :assigned_conversations_belong_to_board
  validate :board_step_belongs_to_board

  before_validation :set_defaults_from_associations

  scope :ordered, -> { order(created_at: :asc) }

  after_create :assign_conversations_on_create
  after_create :sync_contacts_from_conversations
  after_create :sync_assigned_agents
  before_update :track_step_change
  before_update :reset_overdue_webhook_marker
  after_update :assign_conversations_on_update
  after_update :sync_contacts_from_conversations
  after_update :sync_assigned_agents
  after_update :accumulate_changes_for_dispatch
  before_destroy :capture_conversations_for_dispatch, prepend: true
  before_destroy :capture_event_data, prepend: true
  after_commit :dispatch_create_event, on: :create
  after_commit :dispatch_update_event, on: :update
  after_commit :dispatch_destroy_event, on: :destroy
  after_commit :dispatch_conversation_events
  after_rollback :clear_accumulated_changes

  # Hours threshold for considering a task "due soon"
  DUE_SOON_THRESHOLD_HOURS = 24

  def overdue?
    due_date.present? && due_date < Time.current
  end

  def due_soon?
    return false if due_date.blank? || overdue?

    due_date <= DUE_SOON_THRESHOLD_HOURS.hours.from_now
  end

  def started?
    start_date.present? && start_date <= Time.current
  end

  def starting_soon?
    return false if start_date.blank? || started?

    start_date <= DUE_SOON_THRESHOLD_HOURS.hours.from_now
  end

  def date_status
    return 'overdue' if overdue?
    return 'due_soon' if due_soon?

    nil
  end

  def status
    board_step.inferred_task_status
  end

  def creator_display_name
    creator&.name || I18n.t('automation.system_name')
  end

  def cached_label_list_array
    (cached_label_list || '').split(',').map(&:strip)
  end

  def push_event_data # rubocop:disable Metrics/AbcSize,Metrics/MethodLength
    reloaded_conversations = conversations.reload
    {
      id: id,
      account_id: account_id,
      board_id: board_id,
      board: {
        id: board.id,
        name: board.name
      },
      board_step_id: board_step_id,
      board_step: {
        id: board_step.id,
        name: board_step.name,
        cancelled: board_step.cancelled,
        color: board_step.color
      },
      created_by_id: created_by_id,
      title: title,
      description: description,
      priority: priority,
      status: status,
      date_status: date_status,
      start_date: start_date,
      due_date: due_date,
      step_changed_at: step_changed_at,
      created_at: created_at,
      updated_at: updated_at,
      contact_ids: contact_ids,
      conversation_ids: reloaded_conversations.pluck(:display_id),
      contacts: contacts.reload.map { |c| contact_push_data(c) },
      conversations: reloaded_conversations.map { |conv| conversation_push_data(conv) },
      assigned_agents: assigned_agents.reload.map do |a|
        { id: a.id, name: a.name, avatar_url: a.avatar_url, availability_status: a.availability_status }
      end,
      labels: cached_label_list_array,
      creator: creator&.push_event_data,
      creator_display_name: creator_display_name
    }.tap do |data|
      # Only include insert_before_task_id when explicitly set (during move operations)
      data[:insert_before_task_id] = @insert_before_task_id if insert_before_task_id_set?
    end
  end

  def reorder_for_user!(user, preference: nil)
    unless preference
      account_user = user.account_users.find_by(account_id: account_id)
      return unless account_user

      preference = account_user.kanban_preference || account_user.build_kanban_preference
    end

    order = preference.tasks_order_for(board_step_id).dup
    order.delete(id)

    if @insert_before_task_id.present?
      index = order.index(@insert_before_task_id.to_i)
      if index
        order.insert(index, id)
      else
        order.push(id)
      end
    else
      order.push(id)
    end

    preference.update_tasks_order!(board_step_id, order)
  end

  private

  def contact_push_data(contact)
    {
      id: contact.id,
      name: contact.name,
      email: contact.email,
      phone_number: contact.phone_number,
      avatar_url: contact.avatar_url,
      additional_attributes: contact.additional_attributes
    }
  end

  def conversation_push_data(conversation)
    {
      id: conversation.id,
      display_id: conversation.display_id,
      status: conversation.status,
      inbox: {
        id: conversation.inbox.id,
        name: conversation.inbox.name,
        channel_type: conversation.inbox.channel_type
      },
      contact: contact_push_data(conversation.contact)
    }
  end

  def track_step_change
    return unless board_step_id_changed?

    self.step_changed_at = Time.current
  end

  def reset_overdue_webhook_marker
    return unless due_date_changed?

    self.overdue_notified_at = nil
  end

  def set_defaults_from_associations # rubocop:disable Metrics/CyclomaticComplexity
    self.board ||= board_step.board if board_step
    self.account ||= board.account if board
    self.creator ||= Current.user if defined?(Current) && Current.respond_to?(:user)
  end

  def scheduled_dates_are_coherent
    return if start_date.blank? || due_date.blank?
    return if start_date <= due_date

    errors.add(:due_date, I18n.t('kanban.tasks.errors.invalid_due_date'))
  end

  def assigned_agents_belong_to_board
    return if assigned_agents.empty? || board.blank?

    return unless assigned_agents.any? { |agent| !board.assigned_agents.exists?(id: agent.id) }

    errors.add(:assigned_agents, I18n.t('kanban.tasks.errors.invalid_assignees'))
  end

  def assigned_conversations_belong_to_board # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    return if board.blank?

    conv_ids = if @conversation_ids_to_assign.present?
                 @conversation_ids_to_assign
               elsif persisted?
                 conversations.pluck(:id)
               else
                 conversations.map(&:id)
               end
    return if conv_ids.blank?

    convs = Conversation.where(id: conv_ids)
    return unless convs.any? { |c| !board.includes_inbox?(c.inbox_id) }

    errors.add(:conversations, I18n.t('kanban.tasks.errors.invalid_conversations'))
  end

  def board_step_belongs_to_board
    return if board_step.blank? || board.blank?
    return if board_step.board_id == board_id

    errors.add(:board_step, I18n.t('kanban.tasks.errors.invalid_board_step'))
  end

  def contacts_belong_to_account
    return if contacts.empty?
    return unless contacts.any? { |contact| contact.account_id != account_id }

    errors.add(:contacts, I18n.t('kanban.tasks.errors.invalid_contact_account'))
  end

  def capture_conversations_for_dispatch
    @conversations_to_dispatch_unassigned = Conversation.where(kanban_task_id: id).pluck(:id)
  end

  def assign_conversations_on_create
    return if @conversation_ids_to_assign.nil?

    @new_conversation_ids = (@conversation_ids_to_assign.presence || [])
    return if @new_conversation_ids.blank?

    conversations = Conversation.where(id: @new_conversation_ids)
    conversations.update_all(kanban_task_id: id) # rubocop:disable Rails/SkipsModelValidations
    @conversations_to_dispatch_assigned = conversations.pluck(:id)
  end

  def assign_conversations_on_update
    return if @conversation_ids_to_assign.nil?

    current_ids = Conversation.where(kanban_task_id: id).pluck(:id)
    new_ids = @conversation_ids_to_assign.map(&:to_i)
    @new_conversation_ids = new_ids

    to_remove_ids = current_ids - new_ids
    to_add_ids = new_ids - current_ids

    if to_remove_ids.present?
      conversations_to_remove = Conversation.where(id: to_remove_ids)
      conversations_to_remove.update_all(kanban_task_id: nil) # rubocop:disable Rails/SkipsModelValidations
      @conversations_to_dispatch_unassigned = to_remove_ids
    end

    if to_add_ids.present?
      conversations_to_add = Conversation.where(id: to_add_ids)
      conversations_to_add.update_all(kanban_task_id: id) # rubocop:disable Rails/SkipsModelValidations
      @conversations_to_dispatch_assigned = to_add_ids
    end

    conversations.reload if to_remove_ids.present? || to_add_ids.present?
  end

  def sync_assigned_agents
    return if @assigned_agent_ids_to_sync.nil?

    current_ids = task_agents.pluck(:agent_id)
    new_ids = @assigned_agent_ids_to_sync

    to_remove_ids = current_ids - new_ids
    to_add_ids = new_ids - current_ids

    # Destroy removed agents (triggers callbacks for conversation sync)
    task_agents.where(agent_id: to_remove_ids).find_each(&:destroy!) if to_remove_ids.present?

    # Create new agents (triggers callbacks for conversation sync)
    to_add_ids.each { |agent_id| task_agents.create!(agent_id: agent_id) } if to_add_ids.present?

    task_agents.reload if to_remove_ids.present? || to_add_ids.present?
    @assigned_agent_ids_to_sync = nil
  end

  def sync_contacts_from_conversations
    return unless @conversation_ids_to_assign

    conversation_contact_ids = if @new_conversation_ids.present?
                                 Conversation.where(id: @new_conversation_ids).pluck(:contact_id).uniq
                               else
                                 []
                               end
    current_contact_ids = contact_ids
    merged_contact_ids = (current_contact_ids + conversation_contact_ids).uniq
    self.contact_ids = merged_contact_ids
  end

  def dispatch_create_event
    Rails.configuration.dispatcher.dispatch(Events::Types::KANBAN_TASK_CREATED, Time.zone.now, task: self)
  end

  def dispatch_update_event
    changes = @accumulated_changes || previous_changes
    Rails.configuration.dispatcher.dispatch(Events::Types::KANBAN_TASK_UPDATED, Time.zone.now, task: self, changed_attributes: changes)
    dispatch_status_change_events(changes)
    @accumulated_changes = nil
  end

  def dispatch_status_change_events(changes = nil)
    changes ||= previous_changes
    return unless changes['board_step_id']

    case status
    when 'completed'
      Rails.configuration.dispatcher.dispatch(Events::Types::KANBAN_TASK_COMPLETED, Time.zone.now, task: self, changed_attributes: changes)
    when 'cancelled'
      Rails.configuration.dispatcher.dispatch(Events::Types::KANBAN_TASK_CANCELLED, Time.zone.now, task: self, changed_attributes: changes)
    end
  end

  def dispatch_destroy_event
    Rails.configuration.dispatcher.dispatch(Events::Types::KANBAN_TASK_DELETED, Time.zone.now, task: @push_event_data)
  end

  def accumulate_changes_for_dispatch
    @accumulated_changes ||= {}
    @accumulated_changes.merge!(previous_changes)
  end

  def clear_accumulated_changes
    @accumulated_changes = nil
  end

  def capture_event_data
    @push_event_data = push_event_data
  end

  def dispatch_conversation_events # rubocop:disable Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
    assigned_ids = @conversations_to_dispatch_assigned || []
    unassigned_ids = @conversations_to_dispatch_unassigned || []

    if assigned_ids.present?
      Conversation.where(id: assigned_ids).each do |c|
        c.dispatch_conversation_updated_event({ 'kanban_task_id' => [nil, id] })
      end
    end

    if unassigned_ids.present?
      Conversation.where(id: unassigned_ids).each do |c|
        c.dispatch_conversation_updated_event({ 'kanban_task_id' => [id, nil] })
      end
    end

    if persisted?
      exclude_ids = assigned_ids + unassigned_ids
      conversations.where.not(id: exclude_ids).each(&:dispatch_conversation_updated_event)
    end

    @conversations_to_dispatch_assigned = nil
    @conversations_to_dispatch_unassigned = nil
  end
end
