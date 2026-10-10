# Somebody picked up a call this account placed with `call.start`.
#
# Only a call placed from the calling flow can be answered, and that flow lives in the
# enterprise half, which is where this is handled. Here there is nothing to update.
class Whatsapp::Session::Inbound::Handlers::CallAnswered < Whatsapp::Session::Inbound::Handlers::Base
  def perform = :ignored
end

Whatsapp::Session::Inbound::Handlers::CallAnswered.prepend_mod_with('Whatsapp::Session::Inbound::Handlers::CallAnswered')
