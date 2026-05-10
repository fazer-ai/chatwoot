class ContactDrop < BaseDrop
  def name
    sanitized_name.try(:split).try(:map, &:capitalize).try(:join, ' ')
  end

  def email
    sanitize_text(@obj.try(:email))
  end

  def phone_number
    sanitize_text(@obj.try(:phone_number))
  end

  # Alias so that {{contact.phone}} (the token surfaced by the message-editor
  # variable picker) resolves to the same value as {{contact.phone_number}}.
  def phone
    sanitize_text(@obj.try(:phone_number))
  end

  def first_name
    parts = sanitized_name.to_s.split
    return nil if parts.empty?

    parts.first.capitalize
  end

  # Falls back to the contact's full name when the name has a single word, so
  # `Olá {{contact.last_name}}` for a contact saved as "Maria" renders "Olá
  # Maria" instead of an empty string. Same idea behind first_name above.
  def last_name
    parts = sanitized_name.to_s.split
    return nil if parts.empty?
    return parts.first.capitalize if parts.size == 1

    parts.last.capitalize
  end

  def custom_attribute
    custom_attributes = @obj.try(:custom_attributes) || {}
    custom_attributes.transform_values { |value| sanitize_text(value) }
                     .transform_keys(&:to_s)
  end

  private

  # Defense in depth: contact-controlled fields like `name` can carry payloads
  # such as <img onerror=...> when the contact comes from incoming messages
  # (WhatsApp/Instagram pass the sender-provided display name verbatim). The
  # rendered Liquid output ends up in two places: the WhatsApp-Cloud template
  # parameter (delivered as plain text) and `messages.content` (rendered in
  # the agent UI). The agent UI already sanitizes via MessageFormatter, but if
  # that ever regresses we don't want a stored-XSS surface. `strip_tags`
  # removes HTML tags without touching legitimate characters like `&` or `<3`,
  # so end-customers and agents see the contact's actual text without the
  # tags that turn into script execution.
  def sanitized_name
    sanitize_text(@obj.try(:name))
  end

  # Strip HTML defensively without breaking legitimate plain-text characters.
  # We can't use Rails' `strip_tags` because it encodes `&` as `&amp;`, which
  # would corrupt the WhatsApp message delivered to the recipient when the
  # contact's name has things like `Mary & John`.
  #
  # We run two Loofah passes:
  #   1. :prune — drops dangerous elements *and their inner text* (so
  #      `<script>alert(1)</script>` becomes empty, not `alert(1)`).
  #   2. :strip — for the remaining benign markup, removes the tag wrapper
  #      and keeps inner text.
  # Final `text(encode_special_chars: false)` outputs plain text without
  # escaping `&`, `<3`, unicode, etc.
  def sanitize_text(value)
    return value if value.blank? || !value.is_a?(String)

    Loofah.fragment(value)
          .scrub!(:prune)
          .scrub!(:strip)
          .text(encode_special_chars: false)
          .strip
  end
end
