# Three intertwined fixes for the funnel chart:
#
# 1. Production was missing every default funnel stage because the original
#    `SeedGlobalFunnelStages` migration guarded the seeder call with
#    `return unless defined?(...)` and a `rescue StandardError` — both of
#    which silently no-op'd on failure. Re-run the seeder here without those
#    silencers so the canonical 9 stages exist everywhere. `find_or_initialize_by`
#    keeps it idempotent.
#
# 2. Rename "Ganho" → "Comparecimento ( ganho )" both on `funnel_stages` and
#    on the historical `funnel_stage_changes` snapshots (`new_stage` /
#    `previous_stage` are strings, so the rename has to chase them or the
#    reports lose the history).
#
# 3. Drop the old chart rule that grouped "Em Agendamento", "Agendado" and
#    "Reagendado" into a single bar. The new rule: "Em Agendamento" leaves the
#    chart entirely (`chart_visible = false`, `chart_group = NULL`), and only
#    "Agendado" + "Reagendado" collapse into the "Agendamento" merged stage.
#    Also bump the display name on the renamed Ganho stage to "Comparecimentos".
class RenameGanhoAndFixFunnelChartRules < ActiveRecord::Migration[7.1]
  def up
    # Step 1: rename the stage before the seeder runs so its
    # `find_or_initialize_by(name: 'Comparecimento ( ganho )')` lookup finds
    # the existing row instead of creating a duplicate alongside it.
    execute("UPDATE funnel_stages SET name = 'Comparecimento ( ganho )' WHERE name = 'Ganho'")
    execute("UPDATE funnel_stage_changes SET new_stage = 'Comparecimento ( ganho )' WHERE new_stage = 'Ganho'")
    execute("UPDATE funnel_stage_changes SET previous_stage = 'Comparecimento ( ganho )' WHERE previous_stage = 'Ganho'")

    # Step 2: ensure all 9 canonical stages exist. Production lost them when
    # the original seed migration silently no-op'd; dev already has them and
    # the seeder is a no-op there. No rescue here: any seeder error should
    # fail the migration loudly instead of leaving the DB half-seeded.
    Funnel::DefaultStagesSeederService.seed_global_stages!

    # Step 3: chart presentation rules. Idempotent — running them on the
    # already-correct dev state is a no-op.
    execute("UPDATE funnel_stages SET chart_display_name = 'Total de leads'  WHERE name = 'Novo Contato'")
    execute("UPDATE funnel_stages SET chart_display_name = 'Comparecimentos' WHERE name = 'Comparecimento ( ganho )'")
    execute("UPDATE funnel_stages SET chart_visible = FALSE, chart_group = NULL WHERE name = 'Em Agendamento'")
    execute("UPDATE funnel_stages SET chart_group = 'Agendamento' WHERE name IN ('Agendado', 'Reagendado')")
    execute("UPDATE funnel_stages SET chart_visible = FALSE WHERE name IN ('No-Show', 'Perdido')")
  end

  def down
    # Restore the pre-rename state. We don't undo the seeder — those stages
    # may be referenced by downstream audit history at this point.
    execute("UPDATE funnel_stages SET chart_group = 'Agendamento' WHERE name = 'Em Agendamento'")
    execute("UPDATE funnel_stages SET chart_visible = TRUE WHERE name = 'Em Agendamento'")
    execute("UPDATE funnel_stages SET chart_display_name = 'Vendas realizadas' WHERE name = 'Comparecimento ( ganho )'")
    execute("UPDATE funnel_stage_changes SET previous_stage = 'Ganho' WHERE previous_stage = 'Comparecimento ( ganho )'")
    execute("UPDATE funnel_stage_changes SET new_stage = 'Ganho' WHERE new_stage = 'Comparecimento ( ganho )'")
    execute("UPDATE funnel_stages SET name = 'Ganho' WHERE name = 'Comparecimento ( ganho )'")
  end
end
