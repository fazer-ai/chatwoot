class CustomExceptions::Disparos::BlockedSendBeta0 < CustomExceptions::Base
  def initialize(data = {})
    super
  end

  def message
    'blocked_send_beta_0'
  end
end
