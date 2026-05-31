class CustomExceptions::Disparos::InvalidDryRun < CustomExceptions::Base
  def initialize(data = {})
    super
  end

  def message
    'invalid_dry_run'
  end
end
