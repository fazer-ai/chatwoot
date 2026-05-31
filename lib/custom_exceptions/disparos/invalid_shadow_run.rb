class CustomExceptions::Disparos::InvalidShadowRun < CustomExceptions::Base
  def initialize(data = {})
    super
  end

  def message
    'invalid_shadow_run'
  end
end
