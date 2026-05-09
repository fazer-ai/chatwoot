class UserDrop < BaseDrop
  def name
    @obj.try(:name).try(:split).try(:map, &:capitalize).try(:join, ' ')
  end

  def available_name
    @obj.try(:available_name)
  end

  def first_name
    parts = @obj.try(:name).to_s.split
    return nil if parts.empty?

    parts.first.capitalize
  end

  # Single-word names fall back to the full name so a token like
  # {{agent.last_name}} for an agent saved as "Bot" renders as "Bot"
  # rather than an empty string.
  def last_name
    parts = @obj.try(:name).to_s.split
    return nil if parts.empty?
    return parts.first.capitalize if parts.size == 1

    parts.last.capitalize
  end
end
