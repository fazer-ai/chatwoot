class RecurringScheduledMessages::RecurrenceDescriptionService
  WEEKDAY_NAMES = %w[Sunday Monday Tuesday Wednesday Thursday Friday Saturday].freeze
  ORDINALS = { 1 => 'first', 2 => 'second', 3 => 'third', 4 => 'fourth', 5 => 'fifth', -1 => 'last' }.freeze

  def initialize(recurrence_rule)
    @rule = recurrence_rule&.with_indifferent_access || {}
  end

  def generate
    return '' if @rule.blank? || @rule[:frequency].blank?

    parts = [frequency_description]
    parts << end_description if @rule[:end_type] && @rule[:end_type] != 'never'
    parts.compact.join(' · ')
  end

  private

  def frequency_description
    case @rule[:frequency]
    when 'daily' then daily_description
    when 'weekly' then weekly_description
    when 'monthly' then monthly_description
    when 'yearly' then yearly_description
    end
  end

  def daily_description
    interval = @rule[:interval] || 1
    interval == 1 ? 'Every day' : "Every #{interval} days"
  end

  def weekly_description
    interval = @rule[:interval] || 1
    days = (@rule[:week_days] || []).sort.map { |d| WEEKDAY_NAMES[d] }

    prefix = interval == 1 ? 'Every week' : "Every #{interval} weeks"
    days.any? ? "#{prefix} on #{days.join(', ')}" : prefix
  end

  def monthly_description
    interval = @rule[:interval] || 1
    prefix = interval == 1 ? 'Monthly' : "Every #{interval} months"

    if @rule[:monthly_type] == 'day_of_week'
      ordinal = ORDINALS[@rule[:monthly_week]] || @rule[:monthly_week].to_s
      weekday = WEEKDAY_NAMES[@rule[:monthly_weekday]] || ''
      "#{prefix} on the #{ordinal} #{weekday}"
    else
      prefix
    end
  end

  def yearly_description
    interval = @rule[:interval] || 1
    interval == 1 ? 'Every year' : "Every #{interval} years"
  end

  def end_description
    case @rule[:end_type]
    when 'on_date'
      "until #{@rule[:end_date]}"
    when 'after_count'
      count = @rule[:end_count]
      "#{count} #{'occurrence'.pluralize(count)}"
    end
  end
end
