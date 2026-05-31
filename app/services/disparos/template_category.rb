# frozen_string_literal: true

# Beta 0 "Disparador Cloud Shadow" — shared template -> category RESOLVER.
#
# Given a Channel (or a raw message_templates array) and a template name, returns
# the MAPPED Disparo enum category ('marketing' / 'utility' / 'authentication')
# of the APPROVED template carrying that name, or nil when there is no match.
#
# nil means: not found, not approved, or the entry carries no category. The
# resolver does NOT default — each caller interprets nil for itself:
#   - GAP A (controller create) treats nil as a 422 (template_category_mismatch).
#   - GAP E (marketing cooldown) treats nil as "does NOT count" (safe direction).
#
# Meta-value -> enum mapping (case-insensitive on BOTH name and category):
#   'MARKETING'       -> 'marketing'
#   'AUTHENTICATION'  -> 'authentication'
#   EVERYTHING ELSE   -> 'utility'   (covers 'UTILITY' AND legacy values such as
#                                     'SHIPPING_UPDATE' / 'ACCOUNT_UPDATE')
# The ONLY category that triggers the marketing cooldown is 'marketing'.
#
# Reads the synced `channel.message_templates` jsonb array (already preloaded by
# AudienceResolver via `preload(inbox: :channel)`), so it introduces no N+1.
class Disparos::TemplateCategory
  APPROVED_STATUS = 'approved'

  # Meta categories that map to a distinct enum value; anything else (UTILITY +
  # all legacy values) falls back to 'utility'.
  MARKETING = 'marketing'
  AUTHENTICATION = 'authentication'
  UTILITY = 'utility'

  # Resolve straight from a Channel (nil-safe: a nil channel / non-WhatsApp
  # channel that does not respond to message_templates yields nil).
  def self.for_channel(channel, template_name)
    templates = channel.respond_to?(:message_templates) ? channel.message_templates : nil
    new(templates).resolve(template_name)
  end

  def initialize(message_templates)
    @templates = message_templates
  end

  # The mapped enum category of the APPROVED template named `template_name`, or
  # nil when no approved entry with a category matches (case-insensitive name).
  def resolve(template_name)
    return nil if template_name.blank?
    return nil unless @templates.is_a?(Array)

    name = template_name.to_s.downcase
    entry = @templates.find { |template| approved_match?(template, name) }
    entry && map_category(entry['category'])
  end

  private

  # True iff `template` is an approved entry for `name` (case-insensitive) that
  # carries a category we can map.
  def approved_match?(template, name)
    return false unless template.is_a?(Hash)

    template['name'].to_s.downcase == name &&
      template['status'].to_s.downcase == APPROVED_STATUS &&
      template['category'].present?
  end

  # Case-insensitive Meta-value -> enum mapping. MARKETING/AUTHENTICATION map
  # 1:1; UTILITY and every legacy value (SHIPPING_UPDATE, ACCOUNT_UPDATE, ...)
  # collapse to 'utility'.
  def map_category(raw)
    case raw.to_s.upcase
    when 'MARKETING' then MARKETING
    when 'AUTHENTICATION' then AUTHENTICATION
    else UTILITY
    end
  end
end
