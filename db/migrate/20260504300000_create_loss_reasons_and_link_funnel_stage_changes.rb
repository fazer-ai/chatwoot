class CreateLossReasonsAndLinkFunnelStageChanges < ActiveRecord::Migration[7.1]
  DEFAULT_REASONS = [
    'Achou caro',
    'Busca convênio',
    'Não quer pagar antecipado',
    'Parou de responder',
    'Sem prazo para decisão',
    'Não é o decisor',
    'Fora da área de atendimento',
    'Agenda indisponível',
    'Não atende necessidade'
  ].freeze

  def up
    unless table_exists?(:loss_reasons)
      create_table :loss_reasons do |t|
        t.string :name, null: false
        t.integer :position, null: false, default: 0
        t.boolean :active, null: false, default: true
        t.timestamps
        t.index :name, unique: true
        t.index :position
      end
    end

    unless column_exists?(:funnel_stages, :requires_loss_reason)
      add_column :funnel_stages, :requires_loss_reason, :boolean, null: false, default: false
    end

    unless column_exists?(:funnel_stage_changes, :loss_reason_id)
      add_reference :funnel_stage_changes, :loss_reason, foreign_key: { on_delete: :nullify }, index: true
    end

    seed_default_reasons!
    mark_perdido_stage!
  end

  def down
    remove_reference :funnel_stage_changes, :loss_reason, foreign_key: true, index: true if column_exists?(:funnel_stage_changes, :loss_reason_id)

    remove_column :funnel_stages, :requires_loss_reason if column_exists?(:funnel_stages, :requires_loss_reason)

    drop_table :loss_reasons if table_exists?(:loss_reasons)
  end

  private

  def seed_default_reasons!
    DEFAULT_REASONS.each_with_index do |name, index|
      reason = LossReason.find_or_initialize_by(name: name)
      reason.position = index if reason.new_record?
      reason.active = true if reason.new_record?
      reason.save!
    end
  end

  def mark_perdido_stage!
    FunnelStage.where(name: 'Perdido').update_all(requires_loss_reason: true) # rubocop:disable Rails/SkipsModelValidations
  end
end
