module LiquidFilters::I18nFilter
  def t(key, *args)
    options = { default: key }
    args.each_slice(2) do |placeholder, value|
      options[placeholder.to_sym] = ERB::Util.html_escape(value.to_s) if placeholder
    end
    I18n.t(key, **options)
  end
end
