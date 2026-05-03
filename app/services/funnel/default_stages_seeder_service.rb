class Funnel::DefaultStagesSeederService
  DEFAULT_STAGES = [
    { name: 'kb-novo',           description: 'Primeiro contato recebido',         position: 0, closed: false, color: '#6b7280' },
    { name: 'kb-triagem',        description: 'Em qualificação / triagem',         position: 1, closed: false, color: '#38bdf8' },
    { name: 'kb-em_agendamento', description: 'Entrando no fluxo de agendamento',  position: 2, closed: false, color: '#3b82f6' },
    { name: 'kb-agendado',       description: 'Consulta agendada com sucesso',     position: 3, closed: false, color: '#8b5cf6' },
    { name: 'kb-reagendado',     description: 'Consulta reagendada',               position: 3, closed: false, color: '#f59e0b' },
    { name: 'kb-confirmado',     description: 'Paciente confirmou presença',       position: 4, closed: false, color: '#10b981' },
    { name: 'kb-no_show',        description: 'Não compareceu',                    position: 5, closed: true,  color: '#f97316' },
    { name: 'kb-fechado',        description: 'Atendimento encerrado',             position: 5, closed: true,  color: '#1e293b' },
    { name: 'kb-perdido',        description: 'Paciente perdido / desistiu',       position: 5, closed: true,  color: '#dc2626' }
  ].freeze

  pattr_initialize [:account!]

  def perform
    DEFAULT_STAGES.each { |stage_attrs| ensure_stage(stage_attrs) }
  end

  private

  def ensure_stage(attrs)
    ensure_label(attrs)
    ensure_funnel_stage(attrs)
  end

  def ensure_label(attrs)
    label = account.labels.find_or_initialize_by(title: attrs[:name])
    label.color = attrs[:color] if label.new_record?
    label.description = attrs[:description] if label.description.blank?
    label.show_on_sidebar = true if label.new_record?
    label.save!
  end

  def ensure_funnel_stage(attrs)
    stage = account.funnel_stages.find_or_initialize_by(name: attrs[:name])
    stage.description ||= attrs[:description]
    stage.position = attrs[:position] if stage.new_record?
    stage.closed = attrs[:closed] if stage.new_record?
    stage.active = true if stage.new_record?
    stage.save!
  end
end
