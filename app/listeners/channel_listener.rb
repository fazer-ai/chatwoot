class ChannelListener < BaseListener
  def conversation_typing_on(event)
    handle_typing_event(event)
  end

  def conversation_recording(event)
    handle_typing_event(event)
  end

  def conversation_typing_off(event)
    handle_typing_event(event)
  end

  def messages_read(event)
    conversation = event.data.values_at(:conversation).first

    channel = conversation&.inbox&.channel
    return unless channel.respond_to?(:send_read_messages)

    messages = conversation.messages.where(message_type: :incoming).map do |message|
      message if message.status != 'read'
    end

    channel.send_read_messages(event.name, messages: messages) if messages.present?
  end

  private

  def handle_typing_event(event)
    is_private, conversation = event.data.values_at(:is_private, :conversation)
    return if is_private

    channel = conversation.inbox.channel
    return unless channel.respond_to?(:toggle_typing_status)

    channel.toggle_typing_status(event.name, conversation: conversation)
  end
end
