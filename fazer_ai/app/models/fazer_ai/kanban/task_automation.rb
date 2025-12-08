# frozen_string_literal: true

# Simple class to represent the Kanban Task Automation executor
# Used with Current.executed_by to customize activity messages when
# conversations are auto-resolved due to kanban task completion
#
# Includes GlobalID::Identification for serialization support when passed
# through ActiveJob (via EventDispatcher)
class FazerAi::Kanban::TaskAutomation
  include GlobalID::Identification

  attr_reader :task

  def initialize(task:)
    @task = task
  end

  # GlobalID requires an id for serialization
  def id
    task.id
  end

  # GlobalID requires find to deserialize
  def self.find(id)
    task = FazerAi::Kanban::Task.find(id)
    new(task: task)
  end
end
