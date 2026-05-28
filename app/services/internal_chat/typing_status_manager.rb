class InternalChat::TypingStatusManager
  include Events::Types

  pattr_initialize [:channel!, :user!, :params!]

  def perform
    case params[:typing_status]
    when 'on'
      dispatch_event(INTERNAL_CHAT_TYPING_ON)
    when 'off'
      dispatch_event(INTERNAL_CHAT_TYPING_OFF)
    end
  end

  private

  def dispatch_event(event)
    Rails.configuration.dispatcher.dispatch(event, Time.zone.now, channel: channel, user: user)
  end
end
