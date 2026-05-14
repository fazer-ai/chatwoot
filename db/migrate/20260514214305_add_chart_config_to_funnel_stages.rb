# Adds presentation-only fields to `funnel_stages` so the conversion-funnel
# chart can rename, merge, and hide stages without forking per-account display
# logic into client code. `name` stays the canonical identifier used by
# FunnelStageChange records.
#
#   - chart_display_name : optional label rendered in the chart instead of
#                          `name`. The Visão Geral table keeps showing `name`.
#   - chart_group        : optional grouping key. Stages sharing a non-blank
#                          chart_group collapse into a single bar in the chart;
#                          the group name itself becomes the displayed label.
#   - chart_visible      : when false, the stage is omitted from the chart
#                          (still counts toward KPI / overview / stage moves).
#
# The data block at the end seeds the rules requested by Auris for the active
# funnel without coupling code to specific stage names. `update_all` is safe
# when no rows match — installations that never created these stages stay put.
class AddChartConfigToFunnelStages < ActiveRecord::Migration[7.1]
  def up
    add_column :funnel_stages, :chart_visible, :boolean, default: true, null: false
    add_column :funnel_stages, :chart_group, :string
    add_column :funnel_stages, :chart_display_name, :string

    execute("UPDATE funnel_stages SET chart_display_name = 'Total de leads' WHERE name = 'Novo Contato'")
    execute("UPDATE funnel_stages SET chart_display_name = 'Vendas realizadas' WHERE name = 'Ganho'")
    execute(<<~SQL.squish)
      UPDATE funnel_stages
         SET chart_group = 'Agendamento'
       WHERE name IN ('Em Agendamento', 'Agendado', 'Reagendado')
    SQL
    execute("UPDATE funnel_stages SET chart_visible = FALSE WHERE name IN ('No-Show', 'Perdido')")
  end

  def down
    remove_column :funnel_stages, :chart_display_name
    remove_column :funnel_stages, :chart_group
    remove_column :funnel_stages, :chart_visible
  end
end
