class RecurringScheduledMessages::CreateNextOccurrenceService
  def initialize(recurring_scheduled_message:, previous_scheduled_message:)
    @recurring = recurring_scheduled_message
    @previous = previous_scheduled_message
  end

  def perform
    @recurring.update!(occurrences_sent: @recurring.occurrences_sent + 1)

    if should_complete?
      complete_series
      return nil
    end

    create_next_scheduled_message
  end

  private

  def should_complete?
    rule = @recurring.recurrence_rule.with_indifferent_access

    case rule[:end_type]
    when 'after_count'
      @recurring.occurrences_sent >= rule[:end_count]
    when 'on_date'
      next_date = calculate_next_date
      next_date.nil? || next_date.to_date > Date.parse(rule[:end_date])
    else
      false
    end
  end

  def complete_series
    @recurring.update!(status: :completed)
    create_completion_activity_message
    dispatch_event(Events::Types::RECURRING_SCHEDULED_MESSAGE_UPDATED)
  end

  def create_next_scheduled_message
    next_date = calculate_next_date
    return nil if next_date.nil?

    scheduled_message = @recurring.scheduled_messages.create!(
      content: @recurring.content,
      template_params: @recurring.template_params,
      scheduled_at: next_date,
      status: :pending,
      account: @recurring.account,
      conversation: @recurring.conversation,
      inbox: @recurring.inbox,
      author: @recurring.author
    )

    copy_attachment(scheduled_message) if @recurring.attachment.attached?
    dispatch_event(Events::Types::RECURRING_SCHEDULED_MESSAGE_UPDATED)
    scheduled_message
  end

  def calculate_next_date
    RecurringScheduledMessages::RecurrenceCalculatorService.new(
      recurrence_rule: @recurring.recurrence_rule,
      last_date: @previous.scheduled_at
    ).next_date
  end

  def copy_attachment(scheduled_message)
    scheduled_message.attachment.attach(@recurring.attachment.blob)
  end

  def create_completion_activity_message
    @recurring.conversation.messages.create!(
      account: @recurring.account,
      inbox: @recurring.inbox,
      message_type: :activity,
      content: I18n.t(
        'conversations.activity.recurring_message_completed',
        count: @recurring.occurrences_sent
      )
    )
  end

  def dispatch_event(event_name)
    Rails.configuration.dispatcher.dispatch(event_name, Time.zone.now, recurring_scheduled_message: @recurring)
  end
end
