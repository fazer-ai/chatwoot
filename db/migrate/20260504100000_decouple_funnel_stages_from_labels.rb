class DecoupleFunnelStagesFromLabels < ActiveRecord::Migration[7.1]
  STAGE_RENAMES = {
    'kb-novo' => { name: 'Novo Contato', color: '#6b7280' },
    'kb-triagem' => { name: 'Em Qualificação', color: '#38bdf8' },
    'kb-em_agendamento' => { name: 'Em Agendamento', color: '#3b82f6' },
    'kb-agendado' => { name: 'Agendado', color: '#10b981' },
    'kb-reagendado' => { name: 'Reagendado', color: '#f59e0b' },
    'kb-confirmado' => { name: 'Confirmado', color: '#8DA43F' },
    'kb-no_show' => { name: 'No-Show', color: '#f97316' },
    'kb-fechado' => { name: 'Ganho', color: '#086944' },
    'kb-perdido' => { name: 'Perdido', color: '#dc2626' }
  }.freeze

  def up
    add_column :funnel_stages, :color, :string unless column_exists?(:funnel_stages, :color)

    unless column_exists?(:conversations, :funnel_stage_id)
      add_reference :conversations, :funnel_stage, foreign_key: { on_delete: :nullify }, index: true
    end

    backfill_funnel_stage_ids_and_strip_labels
    rename_stages_and_set_colors
    drop_legacy_funnel_labels
    backfill_default_color_for_unrenamed_stages

    change_column_null :funnel_stages, :color, false
  end

  def down
    change_column_null :funnel_stages, :color, true if column_exists?(:funnel_stages, :color)

    if column_exists?(:conversations, :funnel_stage_id)
      remove_reference :conversations, :funnel_stage, foreign_key: { on_delete: :nullify }, index: true
    end

    remove_column :funnel_stages, :color if column_exists?(:funnel_stages, :color)
  end

  private

  def backfill_funnel_stage_ids_and_strip_labels
    STAGE_RENAMES.each_key do |old_name|
      stage = FunnelStage.find_by(name: old_name)
      next unless stage

      Conversation.where('cached_label_list ILIKE ?', "%#{old_name}%").find_each(batch_size: 200) do |conv|
        labels = Array(conv.label_list)
        next unless labels.include?(old_name)

        conv.update_columns(funnel_stage_id: stage.id) # rubocop:disable Rails/SkipsModelValidations
        conv.update!(label_list: labels - [old_name])
      end
    end
  end

  def rename_stages_and_set_colors
    STAGE_RENAMES.each do |old_name, attrs|
      stage = FunnelStage.find_by(name: old_name)
      next unless stage

      stage.update!(name: attrs[:name], color: attrs[:color])
    end
  end

  def drop_legacy_funnel_labels
    Label.where(title: STAGE_RENAMES.keys).destroy_all
  end

  def backfill_default_color_for_unrenamed_stages
    FunnelStage.where(color: nil).find_each { |s| s.update!(color: '#94a3b8') }
  end
end
