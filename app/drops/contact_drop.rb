class ContactDrop < BaseDrop
  def name
    @obj.try(:name).try(:split).try(:map, &:capitalize).try(:join, ' ')
  end

  def email
    @obj.try(:email)
  end

  def phone_number
    @obj.try(:phone_number)
  end

  def first_name
    parts = @obj.try(:name).to_s.split
    return nil if parts.empty?

    parts.first.capitalize
  end

  # Falls back to the contact's full name when the name has a single word, so
  # `Olá {{contact.last_name}}` for a contact saved as "Maria" renders "Olá
  # Maria" instead of an empty string. Same idea behind first_name above.
  def last_name
    parts = @obj.try(:name).to_s.split
    return nil if parts.empty?
    return parts.first.capitalize if parts.size == 1

    parts.last.capitalize
  end

  def custom_attribute
    custom_attributes = @obj.try(:custom_attributes) || {}
    custom_attributes.transform_keys(&:to_s)
  end
end
