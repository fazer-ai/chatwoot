# Add your own tasks in files placed in lib/tasks ending in .rake,
# for example lib/tasks/capistrano.rake, and they will automatically be available to Rake.

require_relative 'config/application'
# Load Enterprise Edition rake tasks if they exist
enterprise_tasks_path = Rails.root.join('enterprise/tasks_railtie.rb').to_s
require enterprise_tasks_path if File.exist?(enterprise_tasks_path)

Rails.application.load_tasks

# Ensure the f_unaccent function used by internal chat search indexes is created
# before db:schema:load runs. This must happen after Rails.application.load_tasks
# so that both `db:schema:load` and `db:internal_chat:ensure_search_functions`
# are guaranteed to be defined.
if Rake::Task.task_defined?('db:schema:load') &&
   Rake::Task.task_defined?('db:internal_chat:ensure_search_functions')
  Rake::Task['db:schema:load'].enhance(['db:internal_chat:ensure_search_functions'])
end

# Re-inject the f_unaccent `execute <<~SQL ...` block into db/schema.rb after
# db:schema:dump rewrites the file. The schema dumper can't capture CREATE
# FUNCTION statements, so without this hook every dump would silently drop the
# block and break db:schema:load downstream.
if Rake::Task.task_defined?('db:schema:dump') &&
   Rake::Task.task_defined?('db:internal_chat:inject_schema_functions')
  Rake::Task['db:schema:dump'].enhance do
    Rake::Task['db:internal_chat:inject_schema_functions'].invoke
  end
end
