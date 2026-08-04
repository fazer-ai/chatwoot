# Captures every IA-driven team assignment as an `AiAssignmentAttempt`
# row, so the "IA → Humano" audit report can answer
# "who was online in the target team at the exact moment the IA tried
# to hand off?" — without depending on the per-minute cron snapshot
# (which could go missing when `:scheduled_jobs` lagged behind).
#
# Hooks the `team.changed` event on the SyncDispatcher, which runs
# inline on the request thread, so `Current.user` is still set to the
# API caller (the n8n credential user for IA flows).
class AiAssignmentListener < BaseListener
  def team_changed(event)
    AiAssignmentAttempt.record_for(event.data[:conversation])
  end
end
