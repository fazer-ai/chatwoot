module FazerAiEe::Call
  # Tells the call widget the voice agent took this call, so it does not ring the agents for it.
  def push_event_data
    super.merge(voice_agent: meta&.dig('voice_agent') == true)
  end
end
