# frozen_string_literal: true

# Beta 0 "Disparador Cloud Shadow" — shared RUNNABLE-DISPARO precondition.
#
# DryRunService and ShadowRunService share the same runnable contract — a disparo
# is runnable iff it has a template_name, at least one inbox AND at least one
# audience filter dimension (kanban_steps or label). They differ ONLY in the
# raised exception class (InvalidDryRun vs InvalidShadowRun), passed in by the
# caller, so each service keeps its own error verbatim.
#
# `include Disparos::RunnableDisparo` exposes `validate_runnable!` / `filter_for`
# as PRIVATE instance methods (module_function preserves visibility), so the call
# sites stay unchanged.
module Disparos::RunnableDisparo
  module_function

  # Raises `error_class` (no-arg, so its fixed message is preserved) when the
  # disparo is missing a template_name, has no inbox, or has neither a
  # kanban_steps nor a label filter dimension.
  def validate_runnable!(disparo, error_class)
    raise error_class if disparo.template_name.blank?
    raise error_class if disparo.disparo_inboxes.empty?

    filter = filter_for(disparo)
    return if filter[:kanban_steps].present? || filter[:label].present?

    raise error_class
  end

  def filter_for(disparo)
    (disparo.audience_filter || {}).with_indifferent_access
  end
end
