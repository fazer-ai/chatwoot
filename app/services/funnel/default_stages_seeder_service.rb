class Funnel::DefaultStagesSeederService
  DEFAULT_STAGES = [
    { name: 'Novo Contato',    description: 'Primeiro contato recebido',         position: 0, closed: false, color: '#6b7280' },
    { name: 'Em Qualificação', description: 'Em qualificação / triagem',         position: 1, closed: false, color: '#38bdf8' },
    { name: 'Em Agendamento',  description: 'Entrando no fluxo de agendamento',  position: 2, closed: false, color: '#3b82f6' },
    { name: 'Agendado',        description: 'Consulta agendada com sucesso',     position: 3, closed: false, color: '#10b981' },
    { name: 'Reagendado',      description: 'Consulta reagendada',               position: 3, closed: false, color: '#f59e0b' },
    { name: 'Confirmado',      description: 'Paciente confirmou presença',       position: 4, closed: false, color: '#8DA43F' },
    { name: 'No-Show',         description: 'Não compareceu',                    position: 5, closed: true,  color: '#f97316' },
    { name: 'Perdido',         description: 'Paciente perdido / desistiu',       position: 6, closed: true,  color: '#dc2626' },
    { name: 'Comparecimento (ganho)', description: 'Paciente compareceu',         position: 7, closed: true,  color: '#086944' }
  ].freeze

  def self.seed_global_stages!
    DEFAULT_STAGES.each do |attrs|
      stage = FunnelStage.find_or_initialize_by(name: attrs[:name])
      stage.description ||= attrs[:description]
      stage.color ||= attrs[:color]
      stage.position = attrs[:position] if stage.new_record?
      stage.closed = attrs[:closed] if stage.new_record?
      stage.active = true if stage.new_record?
      stage.save!
    end
  end
end
