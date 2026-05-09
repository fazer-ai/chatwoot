module AiStatusActivityMessageHandler
  extend ActiveSupport::Concern

  private

  # Emits an activity message ("X acionou a IA" / "X desligou a IA") whenever the
  # effective AI status changes. Works in both account modes:
  #   - attribute mode: triggered by `ai_enabled` column saved_change
  #   - legacy mode:    triggered by add/remove of the `agente-off` label
  def handle_ai_status_change(user_name)
    new_state = ai_status_change_new_state
    return if new_state.nil?

    content = ai_status_activity_content(new_state, user_name)
    return if content.blank?

    ::Conversations::ActivityMessageJob.perform_later(self, activity_message_params(content))
  end

  def ai_status_change_new_state
    if account.ai_status_uses_attribute?
      return nil unless saved_change_to_attribute?(:ai_enabled)

      ai_enabled
    else
      detect_ai_state_from_label_change
    end
  end

  def detect_ai_state_from_label_change
    return nil unless saved_change_to_label_list?

    previous_labels, current_labels = previous_changes[:label_list]
    return nil unless previous_labels.is_a?(Array) && current_labels.is_a?(Array)

    had_off = previous_labels.include?('agente-off')
    has_off = current_labels.include?('agente-off')
    return nil if had_off == has_off

    !has_off
  end

  def ai_status_activity_content(new_state, user_name)
    key = new_state ? 'enabled' : 'disabled'
    if user_name.present?
      I18n.t("conversations.activity.ai_status.#{key}", user_name: user_name)
    else
      I18n.t("conversations.activity.ai_status.#{key}_system")
    end
  end
end
