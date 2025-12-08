# frozen_string_literal: true

if defined?(FactoryBot)
  fazer_ai_factories = Rails.root.join('fazer_ai/spec/factories')
  FactoryBot.definition_file_paths << fazer_ai_factories if fazer_ai_factories.exist? && FactoryBot.definition_file_paths.exclude?(fazer_ai_factories)
end
