# frozen_string_literal: true

# Beta 0 "Disparador Cloud Shadow" — shared BULK-MARKER key contract.
#
# Single definition of the per-template dedup/cooldown marker shape
# `bulk_template_<template_name>_sent_at`. The EligibilityEngine (dedup +
# marketing cooldown) keys off this exact contract; centralizing it here keeps
# the prefix/suffix, the per-template key builder and the generic matcher from
# drifting apart.
module Disparos::BulkMarker
  PREFIX = 'bulk_template_'
  SUFFIX = '_sent_at'

  # Generic `bulk_template_<any>_sent_at` matcher (any non-empty template name).
  REGEX = /\A#{PREFIX}.+#{SUFFIX}\z/

  module_function

  # The per-template dedup key: `bulk_template_<template_name>_sent_at`.
  def key(template_name)
    "#{PREFIX}#{template_name}#{SUFFIX}"
  end

  # True iff `key` has the generic bulk-marker shape. Mirrors the prefix/suffix
  # affix test (kept as start_with?/end_with? so existing call-site semantics —
  # which accept a degenerate empty-name key — are preserved exactly).
  def marker_key?(key)
    key_str = key.to_s
    key_str.start_with?(PREFIX) && key_str.end_with?(SUFFIX)
  end
end
