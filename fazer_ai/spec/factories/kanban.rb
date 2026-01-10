# frozen_string_literal: true

FactoryBot.define do
  factory :kanban_board, class: 'FazerAi::Kanban::Board' do
    association :account
    sequence(:name) { |n| "Kanban Board #{n}" }
    description { 'Sample board' }
    settings { {} }
  end

  factory :kanban_board_step, class: 'FazerAi::Kanban::BoardStep' do
    association :board, factory: :kanban_board
    sequence(:name) { |n| "Step #{n}" }
    description { 'Initial qualification' }
    color { '#475569' }
  end

  factory :kanban_task, class: 'FazerAi::Kanban::Task' do
    association :board, factory: :kanban_board
    title { "Task #{SecureRandom.hex(4)}" }
    description { 'Follow up with the lead' }
    priority { nil }

    after(:build) do |task|
      task.account ||= task.board.account
      task.board_step ||= build(:kanban_board_step, board: task.board)
      task.creator ||= build(:user, account: task.account)
    end
  end

  factory :kanban_audit_event, class: 'FazerAi::Kanban::AuditEvent' do
    association :task, factory: :kanban_task
    action { 'task.updated' }
    metadata { { field: 'priority', from: nil, to: 'high' } }

    after(:build) do |event|
      event.account ||= event.task.account
      event.actor ||= build(:user, account: event.account)
    end
  end

  factory :kanban_board_agent, class: 'FazerAi::Kanban::BoardAgent' do
    association :board, factory: :kanban_board

    after(:build) do |agent|
      agent.agent ||= build(:user, account: agent.board.account)
    end
  end

  factory :kanban_board_inbox, class: 'FazerAi::Kanban::BoardInbox' do
    association :board, factory: :kanban_board

    after(:build) do |link|
      link.inbox ||= create(:inbox, account: link.board.account)
    end
  end

  factory :kanban_task_contact, class: 'FazerAi::Kanban::TaskContact' do
    association :task, factory: :kanban_task

    after(:build) do |task_contact|
      task_contact.contact ||= build(:contact, account: task_contact.task.account)
    end
  end

  factory :kanban_account_user_preference, class: 'FazerAi::Kanban::AccountUserPreference' do
    association :account_user
    preferences { {} }
  end

  factory :kanban_task_agent, class: 'FazerAi::Kanban::TaskAgent' do
    association :task, factory: :kanban_task

    after(:build) do |task_agent|
      task_agent.agent ||= build(:user, account: task_agent.task.account)
    end
  end
end
