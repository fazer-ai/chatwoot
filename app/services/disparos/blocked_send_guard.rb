class Disparos::BlockedSendGuard
  # Beta 0 is a read-only/shadow module: it NEVER sends real messages.
  # This guard hard-raises unconditionally. There is no enable path.
  def self.block!(_context = {})
    raise CustomExceptions::Disparos::BlockedSendBeta0
  end
end
