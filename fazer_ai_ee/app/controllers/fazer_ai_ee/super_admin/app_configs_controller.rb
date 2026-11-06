module FazerAiEe::SuperAdmin::AppConfigsController
  private

  # The email logo and the brand color, each listed next to its dashboard counterpart.
  def custom_branding_options
    super.flat_map do |option|
      case option
      when 'LOGO_DARK' then [option, 'LOGO_EMAIL']
      when 'BRAND_NAME' then [option, 'BRAND_COLOR']
      else [option]
      end
    end
  end
end
