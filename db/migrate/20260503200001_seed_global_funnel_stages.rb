class SeedGlobalFunnelStages < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    return unless defined?(Funnel::DefaultStagesSeederService)

    Funnel::DefaultStagesSeederService.seed_global_stages!
  rescue StandardError => e
    Rails.logger.error("Failed to seed global funnel stages: #{e.message}")
  end

  def down
    # Leave global stages in place — they may be referenced by audit history.
  end
end
