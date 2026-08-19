# WhatsApp's own limits on the account behind the session: the wait before it may
# start new conversations, and how many it may start. They arrive out of band and stay
# on the connection record until the provider says otherwise.
class Whatsapp::Session::Inbound::Handlers::AccountLimits < Whatsapp::Session::Inbound::Handlers::Base
  def perform
    case payload&.wire_type
    when 'account.reachout_timelock' then write('reachout_time_lock', payload.reachout_time_lock)
    when 'account.new_chat_cap' then write('new_chat_cap', payload.new_chat_cap)
    else :ignored
    end
  end

  private

  # Written straight to the connection record rather than through ConnectionStateWriter:
  # these are the sticky keys, and they must not carry a connection state with them.
  def write(key, value)
    return :ignored if value.nil?

    channel.with_lock do
      connection = (channel.provider_connection.presence || {}).merge(key => value)
      next :ignored if connection == channel.provider_connection

      channel.update_provider_connection!(connection)
      :handled
    end
  end
end
