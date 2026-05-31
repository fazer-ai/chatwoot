# frozen_string_literal: true

# Beta 0 "Disparador Cloud Shadow" — Eligibility Result.
#
# Dumb value object returned by Disparos::EligibilityEngine for a single
# candidate conversation. All precedence/decision logic lives in the engine;
# this object only carries the outcome.
#
#   - skip_reasons:        Array<String>, EVERY applicable skip reason (AC44).
#   - primary_skip_reason: String or nil, highest-precedence reason present.
#   - eligible?:           true iff there are no skip reasons.
Disparos::EligibilityResult = Struct.new(:skip_reasons, :primary_skip_reason) do
  def eligible?
    skip_reasons.empty?
  end
end
