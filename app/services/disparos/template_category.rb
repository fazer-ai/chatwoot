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
# The CATEGORY value is always mapped case-insensitively:
#   'MARKETING'       -> 'marketing'
#   'AUTHENTICATION'  -> 'authentication'
#   EVERYTHING ELSE   -> 'utility'   (covers 'UTILITY' AND legacy values such as
#                                     'SHIPPING_UPDATE' / 'ACCOUNT_UPDATE')
#
# The template NAME match is PARAMETERIZED by `exact:` because the two callers
# need OPPOSITE fail-safe directions and a single mode cannot satisfy both:
#
#   - exact: false (DEFAULT) — case-INSENSITIVE name match. This is the GENEROUS
#     classifier used by the marketing-cooldown path (EligibilityEngine#marker_category):
#     a historical / externally-written marker `bulk_template_PROMO_BLAST_sent_at`
#     whose synced template is `promo_blast` must STILL resolve to MARKETING so the
#     cooldown trips. Fail-safe here = do NOT fail open: a marker that MIGHT be
#     marketing still blocks. This is the default so any caller gets the safe
#     classifier behavior.
#
#   - exact: true — case-SENSITIVE exact name match. Used by the controller's
#     create-time template_category_matches? guard so the OPERATOR's submitted
#     `template_name` must EXACTLY match a synced approved template. Fail-safe here
#     = STRICT: a mis-cased name resolves to nil → category mismatch → 422, so the
#     persisted disparo's `template_name` is always canonical and the engine's exact
#     approval allowlist + exact `BulkMarker.key` dedup all agree end-to-end. Never
#     persisted, so it can never reach the engine to be mis-marked. No fail-open.
#
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
  # channel that does not respond to message_templates yields nil). `exact:` toggles
  # the name-match case-sensitivity (see the class docstring): default false is the
  # GENEROUS classifier (cooldown safe direction); true is the STRICT create guard.
  def self.for_channel(channel, template_name, exact: false)
    templates = channel.respond_to?(:message_templates) ? channel.message_templates : nil
    new(templates).resolve(template_name, exact: exact)
  end

  def initialize(message_templates)
    @templates = message_templates
  end

  # The mapped enum category of the APPROVED template named `template_name`, or
  # nil when no approved entry with a category matches. `exact:` selects the name
  # match mode: false (default) is case-INSENSITIVE (generous), true is
  # case-SENSITIVE (strict). See the class docstring for why the two callers differ.
  def resolve(template_name, exact: false)
    return nil if template_name.blank?
    return nil unless @templates.is_a?(Array)

    name = template_name.to_s
    entry = @templates.find { |template| approved_match?(template, name, exact) }
    entry && map_category(entry['category'])
  end

  private

  # True iff `template` is an approved entry for `name` that carries a category we
  # can map. The name match is case-SENSITIVE when `exact` is true and
  # case-INSENSITIVE otherwise; `status` is always compared case-insensitively
  # (Meta syncs it as 'approved' / 'APPROVED').
  def approved_match?(template, name, exact)
    return false unless template.is_a?(Hash)

    name_matches?(template['name'].to_s, name, exact) &&
      template['status'].to_s.downcase == APPROVED_STATUS &&
      template['category'].present?
  end

  # Exact (case-sensitive) when `exact`, else case-insensitive (casecmp?).
  def name_matches?(candidate, name, exact)
    exact ? candidate == name : candidate.casecmp?(name)
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
