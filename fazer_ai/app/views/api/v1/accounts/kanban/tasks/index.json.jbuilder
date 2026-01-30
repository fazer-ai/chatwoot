json.tasks do
  json.array! @tasks do |task|
    json.partial! 'task', task: task
  end
end

json.meta do
  json.total_count @total_count
  json.page @page
  json.per_page @per_page
  json.has_more @has_more
end
