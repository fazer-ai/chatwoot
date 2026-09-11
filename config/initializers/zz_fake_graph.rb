# Não versionado: redireciona a Graph da Meta para o servidor falso da rodada.
if ENV['FAKE_GRAPH_BASE_URI'].present?
  Rails.application.config.to_prepare do
    [Whatsapp::FacebookApiClient, Whatsapp::HealthService].each do |klass|
      klass.send(:remove_const, :BASE_URI) if klass.const_defined?(:BASE_URI, false)
      klass.const_set(:BASE_URI, ENV.fetch('FAKE_GRAPH_BASE_URI'))
    end
  end
end
