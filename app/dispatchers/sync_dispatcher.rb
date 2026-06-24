class SyncDispatcher < BaseDispatcher
  def dispatch(event_name, timestamp, data)
    event_object = Events::Base.new(event_name, timestamp, data)
    publish(event_object.method_name, event_object)
  end

  def listeners
    [
      ActionCableListener.instance,
      AgentBotListener.instance,
      # Sync (not async): we need `Current.user` to identify the IA.
      AiAssignmentListener.instance
    ]
  end
end
