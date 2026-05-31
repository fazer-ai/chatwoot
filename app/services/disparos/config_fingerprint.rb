# frozen_string_literal: true

# Beta 0 "Disparador Cloud Shadow" — config FINGERPRINT helper.
#
# A deterministic SHA over the disparo's config dimensions, used by GAP B to gate
# the shadow run: DryRunService stores this on the snapshot it writes, and
# ShadowRunService recomputes it from the disparo's CURRENT config and refuses to
# run if it drifted from the approved snapshot. So an operator can never approve
# one preview and persist a set built from a different template / inbox set /
# audience filter / conversation status.
#
# Dimensions (the config that changes WHICH leads get persisted):
#   - template_name
#   - template_category (the enum reader: 'marketing' / 'utility' / 'authentication')
#   - audience_filter   (canonicalized: keys + array values sorted, so equal
#                        filters in any order hash identically)
#   - inbox_ids         (disparo.disparo_inboxes.pluck(:inbox_id), SORTED)
#   - conversation_status ('open' / 'all')
#
# This is NOT the removed wf15 filter_digest — it is new, simple, and self-contained.
class Disparos::ConfigFingerprint
  def self.for(disparo)
    new(disparo).digest
  end

  def initialize(disparo)
    @disparo = disparo
  end

  def digest
    Digest::SHA256.hexdigest(canonical_payload.to_json)
  end

  private

  def canonical_payload
    {
      template_name: @disparo.template_name,
      template_category: @disparo.template_category,
      audience_filter: canonical_filter,
      inbox_ids: @disparo.disparo_inboxes.pluck(:inbox_id).sort,
      conversation_status: @disparo.conversation_status
    }
  end

  # Canonicalize the audience_filter so two filters that are equal up to key/value
  # ordering produce the same fingerprint: sort the hash by key and sort every
  # array value. Beta 0 filter values are arrays of strings (kanban_steps, label).
  def canonical_filter
    filter = (@disparo.audience_filter || {}).stringify_keys
    filter.keys.sort.to_h do |key|
      value = filter[key]
      [key, value.is_a?(Array) ? value.map(&:to_s).sort : value]
    end
  end
end
