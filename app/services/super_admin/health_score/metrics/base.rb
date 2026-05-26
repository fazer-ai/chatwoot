# Base interface for the 5 Health Score metrics. Each subclass receives an
# account + a reference date and returns a uniform result hash consumed by
# `SuperAdmin::HealthScore::Calculator`.
#
# Result shape:
#   { sub_score: 0..100 | nil, raw: { ... }, missing: Boolean, reason: String | nil }
#
# A metric returns `missing: true` when the data needed to evaluate it is
# absent (e.g. account has no WhatsApp inbox, or has no manager role, or
# falls inside the implementation phase). The aggregator then redistributes
# that metric's weight proportionally across the remaining ones.
class SuperAdmin::HealthScore::Metrics::Base
  attr_reader :account, :on

  def initialize(account, on:)
    @account = account
    @on = on
  end

  def compute
    raise NotImplementedError
  end

  private

  def missing(reason, raw = {})
    { sub_score: nil, raw: raw, missing: true, reason: reason.to_s }
  end

  def present(sub_score, raw)
    { sub_score: sub_score, raw: raw, missing: false, reason: nil }
  end
end
