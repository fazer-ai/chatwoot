class AddDiagnosticToWf15BaselineRuns < ActiveRecord::Migration[7.1]
  # PARITY-INTEGRITY (Task 2): wf15_footprint reconstructs ONLY wf15's SENT leads
  # (all marked eligible) — it has no skipped/opt-out/dedup/skip-reason data, so it
  # is a DIAGNOSTIC reconstruction, NOT a PRD Phase 5 parity baseline. This flag makes
  # that distinction STRUCTURAL: a diagnostic baseline drives ShadowCompareService to a
  # NON-AUTHORITATIVE verdict (overall_pass = nil), so it can never be read as a pass.
  # Additive + reversible: existing rows default to false (a real, authoritative baseline).
  def change
    add_column :wf15_baseline_runs, :diagnostic, :boolean, null: false, default: false
  end
end
