module LiquidFilters::I18nFilter
  def t(key, *args)
    result = I18n.t(key, default: key)
    args.each_slice(2) do |placeholder, value|
      result = result.gsub("%{#{placeholder}}", value.to_s) if placeholder
    end
    result
  end
end
