# frozen_string_literal: true

# Beta 0 "Disparador Cloud Shadow" — Cost Estimator.
#
# Minimal, static, configurable price source. Given a category and an eligible
# count, returns the estimated cost in USD cents, or nil (unknown_price) when no
# price is configured/resolvable for that category. Per the PRD: "tabela
# estática configurável por categoria/país", "registrar fonte da tabela",
# "permitir unknown_price". PTAX/BRL conversion is intentionally out of scope.
#
# The price table is injectable (constructor `prices:`) so DryRunService can be
# driven with a configured estimator (integer path) or an unconfigured one
# (nil/unknown_price path). `#source` is a documented label recording where the
# table came from; it is surfaced on the summary, never persisted into the
# snapshot jsonb counts.
class Disparos::CostEstimator
  # Provisional static table. USD cents per delivered template message, keyed by
  # Meta template category. Reconcile vs the real Meta price list before Phase 5.
  DEFAULT_PRICES = {}.freeze

  DEFAULT_SOURCE = 'static_table_beta0'

  attr_reader :source

  def initialize(prices: DEFAULT_PRICES, source: DEFAULT_SOURCE)
    @prices = prices.transform_keys(&:to_s)
    @source = source
  end

  # Returns total cost in USD cents (Integer) for `eligible_count` messages of
  # the given `category`, or nil when the category has no configured price
  # (unknown_price). A nil/blank category resolves to unknown_price as well.
  def perform(eligible_count:, category: nil)
    unit_cents = @prices[category.to_s]
    return if unit_cents.nil?

    unit_cents * eligible_count
  end
end
