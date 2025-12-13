# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::Kanban::AuditEventJob do
  subject(:perform_job) do
    described_class.perform_now(
      task_id: task.id,
      account_id: account.id,
      action: action,
      metadata: metadata,
      performed_by_id: performed_by_id,
      occurred_at: occurred_at
    )
  end

  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }
  let(:task) { create(:kanban_task, board: board) }
  let(:actor) { create(:user, account: account) }
  let(:metadata) { { status: 'open' } }
  let(:action) { 'task.updated' }
  let(:occurred_at) { Time.zone.parse('2024-10-02 11:30:00 UTC') }
  let(:performed_by_id) { actor.id }

  before do
    account.enable_features('kanban')
  end

  it 'delegates to the audit logger with resolved records' do
    expect(FazerAi::Kanban::AuditLogger).to receive(:log).with(
      task: task,
      action: action,
      metadata: metadata,
      performed_by: actor,
      occurred_at: occurred_at
    )

    perform_job
  end

  it 'resolves to a nil actor when the performer id is absent' do
    expect(FazerAi::Kanban::AuditLogger).to receive(:log).with(
      task: task,
      action: action,
      metadata: metadata,
      performed_by: nil,
      occurred_at: occurred_at
    )

    described_class.perform_now(
      task_id: task.id,
      account_id: account.id,
      action: action,
      metadata: metadata,
      performed_by_id: nil,
      occurred_at: occurred_at
    )
  end

  it 'skips logging when the kanban feature is disabled for the account' do
    account.disable_features('kanban')

    expect(FazerAi::Kanban::AuditLogger).not_to receive(:log)

    perform_job
  end

  it 'silently drops the job if the task is not in the account' do
    other_account = create(:account)
    other_account.enable_features('kanban')

    expect(FazerAi::Kanban::AuditLogger).not_to receive(:log)

    described_class.perform_now(
      task_id: task.id,
      account_id: other_account.id,
      action: action,
      metadata: metadata,
      performed_by_id: nil,
      occurred_at: occurred_at
    )
  end
end
