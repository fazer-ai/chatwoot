class Funnel::MoveConversationService
  include Events::Types

  Result = Struct.new(:conversation, :previous_stage, :new_stage, :change, keyword_init: true)

  pattr_initialize [:account!, :conversation_display_id!, :target_stage_name!,
                    { user: nil, reason: nil, source: 'web' }]

  def perform
    raise ActiveRecord::RecordNotFound, 'Conversation not found' unless conversation
    raise ArgumentError, "Stage '#{target_stage_name}' is not active" unless target_stage

    previous_stage = conversation.funnel_stage

    ActiveRecord::Base.transaction do
      apply_stage_change!
      record_audit!(previous_stage&.name)
    end

    dispatch_funnel_updated_event(previous_stage)

    Result.new(
      conversation: conversation,
      previous_stage: previous_stage&.name,
      new_stage: target_stage.name,
      change: @change
    )
  end

  private

  def conversation
    @conversation ||= account.conversations.find_by(display_id: conversation_display_id)
  end

  def target_stage
    @target_stage ||= FunnelStage.active.find_by(name: target_stage_name)
  end

  def apply_stage_change!
    conversation.update!(funnel_stage_id: target_stage.id)
  end

  def record_audit!(previous_stage_name)
    @change = account.funnel_stage_changes.create!(
      inbox_id: conversation.inbox_id,
      contact_id: conversation.contact_id,
      conversation_id: conversation.id,
      previous_stage: previous_stage_name,
      new_stage: target_stage.name,
      cycle: next_cycle_for(previous_stage_name),
      reason: reason,
      source: source,
      user: user
    )
  end

  def next_cycle_for(previous_stage_name)
    return 1 if previous_stage_name.blank?

    last_cycle = account.funnel_stage_changes
                        .where(conversation_id: conversation.id, new_stage: target_stage.name)
                        .maximum(:cycle) || 0
    last_cycle + 1
  end

  def dispatch_funnel_updated_event(previous_stage)
    Rails.configuration.dispatcher.dispatch(
      FUNNEL_UPDATED,
      Time.zone.now,
      conversation: conversation,
      previous_stage: previous_stage,
      new_stage: target_stage,
      reason: reason,
      source: source,
      user: user,
      change: @change
    )
  end
end
