# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::Kanban::AuditLogger do
  subject(:log_event) do
    described_class.log(
      task: task,
      action: action,
      metadata: metadata,
      performed_by: actor,
      occurred_at: occurred_at
    )
  end

  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }
  let(:task) { create(:kanban_task, board: board) }
  let(:actor) { create(:user, account: account) }
  let(:action) { 'task.updated' }
  let(:metadata) { { field: :priority, from: :medium, to: :high } }
  let(:occurred_at) { Time.zone.parse('2024-10-01 09:15:00 UTC') }

  before do
    account.enable_features('kanban')
  end

  it 'persists an audit event with sanitized metadata and actor' do # rubocop:disable RSpec/MultipleExpectations
    expect { log_event }.to change(FazerAi::Kanban::AuditEvent, :count).by(1)

    event = FazerAi::Kanban::AuditEvent.last
    expect(event.account).to eq(account)
    expect(event.task).to eq(task)
    expect(event.actor).to eq(actor)
    expect(event.action).to eq(action)
    expect(event.metadata).to eq({ 'field' => 'priority', 'from' => 'medium', 'to' => 'high' })
    expect(event.created_at).to eq(occurred_at)
    expect(event.updated_at).to eq(occurred_at)
  end

  it 'skips logging when the kanban feature is disabled' do
    account.disable_features('kanban')

    expect { log_event }.not_to change(FazerAi::Kanban::AuditEvent, :count)
  end

  it 'deep stringifies metadata keys' do
    payload = { nested: { previous_owner: :alex } }

    described_class.log(task: task, action: action, metadata: payload)

    expect(FazerAi::Kanban::AuditEvent.last.metadata).to eq({ 'nested' => { 'previous_owner' => 'alex' } })
  end
end
