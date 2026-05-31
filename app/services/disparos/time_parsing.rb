# frozen_string_literal: true

require 'time'

# Beta 0 "Disparador Cloud Shadow" — shared STRICT ISO8601 time parsing.
#
# Single source of truth for the strict `Time.iso8601` probe used across the
# read-only pipeline. Unlike Time.zone.parse, Time.iso8601 rejects digit-garbage
# (e.g. 'garbage123') instead of coercing it to today 00:00, so an unparseable
# window value surfaces as invalid and a garbage dedup value never fabricates a
# template_sent_last_7d hit.
#
# `include Disparos::TimeParsing` exposes `parse_time` as a PRIVATE instance
# method (module_function keeps the call sites' visibility unchanged).
module Disparos::TimeParsing
  module_function

  # Returns nil for a blank value or an unparseable string; a valid ISO8601
  # string parses to a Time. Rescues ArgumentError/TypeError to nil.
  def parse_time(value)
    return if value.blank?

    Time.iso8601(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
