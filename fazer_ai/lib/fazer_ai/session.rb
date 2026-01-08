# frozen_string_literal: true

module FazerAi::Session
  @mutex = Mutex.new

  class << self
    def session_id
      @session_id || @mutex.synchronize { @session_id ||= SecureRandom.uuid }
    end

    def reset!
      @mutex.synchronize { @session_id = nil }
    end
  end
end
