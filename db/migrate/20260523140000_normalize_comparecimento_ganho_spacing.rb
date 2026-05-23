# Cosmetic rename: `Comparecimento ( ganho )` → `Comparecimento (ganho)`
# (drop the spaces inside the parens). Has to chase the stored history on
# `funnel_stage_changes.new_stage` / `previous_stage` too because they are
# string snapshots, not foreign keys — otherwise the conversion report
# stops finding the attendance stage by name.
class NormalizeComparecimentoGanhoSpacing < ActiveRecord::Migration[7.1]
  OLD_NAME = 'Comparecimento ( ganho )'.freeze
  NEW_NAME = 'Comparecimento (ganho)'.freeze

  def up
    execute("UPDATE funnel_stages SET name = #{quote(NEW_NAME)} WHERE name = #{quote(OLD_NAME)}")
    execute("UPDATE funnel_stage_changes SET new_stage = #{quote(NEW_NAME)} WHERE new_stage = #{quote(OLD_NAME)}")
    execute("UPDATE funnel_stage_changes SET previous_stage = #{quote(NEW_NAME)} WHERE previous_stage = #{quote(OLD_NAME)}")
  end

  def down
    execute("UPDATE funnel_stages SET name = #{quote(OLD_NAME)} WHERE name = #{quote(NEW_NAME)}")
    execute("UPDATE funnel_stage_changes SET new_stage = #{quote(OLD_NAME)} WHERE new_stage = #{quote(NEW_NAME)}")
    execute("UPDATE funnel_stage_changes SET previous_stage = #{quote(OLD_NAME)} WHERE previous_stage = #{quote(NEW_NAME)}")
  end

  private

  def quote(value)
    ActiveRecord::Base.connection.quote(value)
  end
end
