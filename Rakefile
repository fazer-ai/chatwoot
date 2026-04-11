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
