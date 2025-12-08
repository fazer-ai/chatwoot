# frozen_string_literal: true

class FazerAiTasksRailtie < Rails::Railtie
  rake_tasks do
    Dir.glob(Rails.root.join('fazer_ai/lib/tasks/**/*.rake')).each { |f| load f }
  end
end
