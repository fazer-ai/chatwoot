class UserDrop < BaseDrop
  def name
    sanitized_name.try(:split).try(:map, &:capitalize).try(:join, ' ')
  end

  def available_name
    sanitize_text(@obj.try(:available_name))
  end

  def email
    sanitize_text(@obj.try(:email))
  end

  def first_name
    parts = sanitized_name.to_s.split
    return nil if parts.empty?

    parts.first.capitalize
  end

  # Single-word names fall back to the full name so a token like
  # {{agent.last_name}} for an agent saved as "Bot" renders as "Bot"
  # rather than an empty string.
  def last_name
    parts = sanitized_name.to_s.split
    return nil if parts.empty?
    return parts.first.capitalize if parts.size == 1

    parts.last.capitalize
  end

  private

  # Defense in depth: see ContactDrop#sanitize_text for rationale.
  def sanitized_name
    sanitize_text(@obj.try(:name))
  end

  def sanitize_text(value)
    return value if value.blank? || !value.is_a?(String)

    Loofah.fragment(value)
          .scrub!(:prune)
          .scrub!(:strip)
          .text(encode_special_chars: false)
          .strip
  end
end
