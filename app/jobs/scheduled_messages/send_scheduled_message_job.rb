class ScheduledMessages::SendScheduledMessageJob < ApplicationJob
  include Events::Types

  queue_as :medium

  def perform(scheduled_message_id)
    scheduled_message = ScheduledMessage.find_by(id: scheduled_message_id)
    return unless scheduled_message

    Current.executed_by = scheduled_message.author if scheduled_message.author.is_a?(AutomationRule)
    scheduled_message.with_lock { send_if_ready(scheduled_message) }
  rescue StandardError => e
    Rails.logger.error("Scheduled message #{scheduled_message_id} failed: #{e.class} #{e.message}")
    if scheduled_message&.pending?
      scheduled_message.update!(status: :failed)
      dispatch_event(scheduled_message)
    end
  ensure
    Current.reset
  end

  private

  def send_if_ready(scheduled_message)
    return unless scheduled_message.pending?
    return unless scheduled_message.due_for_sending?

    message = send_message(scheduled_message)
    update_scheduled_message_status(scheduled_message, message)
  end

  def send_message(scheduled_message)
    params = {
      content: scheduled_message.content,
      private: false,
      message_type: 'outgoing',
      scheduled_message: scheduled_message
    }
    params[:template_params] = scheduled_message.template_params if scheduled_message.template_params.present?
    params[:attachments] = [scheduled_message.attachment.blob.signed_id] if scheduled_message.attachment.attached?
    params.merge!(scheduled_message_content_attributes(scheduled_message))

    Messages::MessageBuilder.new(message_author(scheduled_message), scheduled_message.conversation, params).perform
  end

  def message_author(scheduled_message)
    scheduled_message.author.is_a?(User) ? scheduled_message.author : nil
  end

  def scheduled_message_content_attributes(scheduled_message)
    return {} unless scheduled_message.author.is_a?(AutomationRule)

    { content_attributes: { automation_rule_id: scheduled_message.author_id } }
  end

  def update_scheduled_message_status(scheduled_message, message)
    return unless scheduled_message.pending?

    new_status = message.failed? ? :failed : :sent
    return if scheduled_message.status == new_status.to_s

    scheduled_message.update!(status: new_status, message: message)
    dispatch_event(scheduled_message)
  end

  def dispatch_event(scheduled_message)
    Rails.configuration.dispatcher.dispatch(SCHEDULED_MESSAGE_UPDATED, Time.zone.now, scheduled_message: scheduled_message)
  end
end
