class CustomExceptions::Disparos::InvalidAudienceFilter < CustomExceptions::Base
  def initialize(data = {})
    super
  end

  def message
    'invalid_audience_filter'
  end
end
