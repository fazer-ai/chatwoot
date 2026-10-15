# A call ended, whichever side ended it and whether or not anybody answered.
#
# A call shown only as an activity line has nothing left to record: the line already says
# it happened. A call taken up by the calling flow is closed by the enterprise half, which
# is where this is handled.
class Whatsapp::Session::Inbound::Handlers::CallTerminate < Whatsapp::Session::Inbound::Handlers::Base
  def perform = :ignored
end

Whatsapp::Session::Inbound::Handlers::CallTerminate.prepend_mod_with('Whatsapp::Session::Inbound::Handlers::CallTerminate')
