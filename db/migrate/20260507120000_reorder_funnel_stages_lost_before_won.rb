class ReorderFunnelStagesLostBeforeWon < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    FunnelStage.where(name: 'Perdido').update_all(position: 6) # rubocop:disable Rails/SkipsModelValidations
    FunnelStage.where(name: 'Ganho').update_all(position: 7) # rubocop:disable Rails/SkipsModelValidations
  end

  def down
    FunnelStage.where(name: 'Perdido').update_all(position: 5) # rubocop:disable Rails/SkipsModelValidations
    FunnelStage.where(name: 'Ganho').update_all(position: 5) # rubocop:disable Rails/SkipsModelValidations
  end
end
