module LabelActivityMessageHandler
  extend ActiveSupport::Concern

  # Internal labels that drive product behavior instead of being user-facing
  # tags. Their changes still happen in the database, but the timeline
  # shouldn't show "X added agente-off" because a dedicated activity (the
  # AiStatusActivityMessageHandler) already explains the change in plain
  # language ("X turned the AI off").
  INTERNAL_LABELS = %w[agente-off].freeze

  private

  def create_label_added(user_name, labels = [])
    create_label_change_activity('added', user_name, labels)
  end

  def create_label_removed(user_name, labels = [])
    create_label_change_activity('removed', user_name, labels)
  end

  def create_label_change_activity(change_type, user_name, labels = [])
    visible_labels = labels.reject { |label| INTERNAL_LABELS.include?(label) }
    return if visible_labels.empty?

    content = I18n.t("conversations.activity.labels.#{change_type}", user_name: user_name, labels: visible_labels.join(', '))
    ::Conversations::ActivityMessageJob.perform_later(self, activity_message_params(content)) if content
  end
end
