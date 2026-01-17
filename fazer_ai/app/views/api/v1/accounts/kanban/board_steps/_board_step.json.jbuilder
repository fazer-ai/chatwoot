json.extract! step,
              :id,
              :board_id,
              :name,
              :description,
              :color,
              :cancelled,
              :created_at,
              :updated_at

json.tasks_count step.tasks_count
json.inferred_task_status step.inferred_task_status
json.filtered_tasks_count filtered_count if defined?(filtered_count) && filtered_count.present?
