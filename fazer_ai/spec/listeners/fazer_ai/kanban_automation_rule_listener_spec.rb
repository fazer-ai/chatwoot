# frozen_string_literal: true

require 'rails_helper'

RSpec.describe FazerAi::KanbanAutomationRuleListener do
  let(:listener) { described_class.instance }
  let(:account) { create(:account) }
  let(:board) { create(:kanban_board, account: account) }
  let!(:step) { create(:kanban_board_step, board: board) }
  let(:task) { create(:kanban_task, account: account, board: board, board_step: step) }
  let(:agent) { create(:user, account: account) }
  let!(:board_agent) { create(:kanban_board_agent, board: board, agent: agent) } # rubocop:disable RSpec/LetSetup

  let(:conditions_filter_service) { instance_double(FazerAi::AutomationRules::KanbanConditionsFilterService) }
  let(:action_service) { instance_double(FazerAi::AutomationRules::KanbanActionService) }

  before do
    allow(account).to receive(:kanban_feature_enabled?).and_return(true)
    allow(FazerAi::AutomationRules::KanbanConditionsFilterService).to receive(:new).and_return(conditions_filter_service)
    allow(FazerAi::AutomationRules::KanbanActionService).to receive(:new).and_return(action_service)
    allow(action_service).to receive(:perform)
  end

  describe 'when kanban feature is disabled' do
    before do
      allow(account).to receive(:kanban_feature_enabled?).and_return(false)
    end

    let!(:automation_rule) do # rubocop:disable RSpec/LetSetup
      create(:automation_rule,
             account: account,
             event_name: 'kanban_task_created',
             conditions: [{ attribute_key: 'kanban_board_id', filter_operator: 'equal_to', values: [board.id], query_operator: nil }],
             actions: [{ action_name: 'assign_agent', action_params: [agent.id] }])
    end

    let(:event) { Events::Base.new('kanban_task_created', Time.zone.now, { task: task }) }

    it 'does not execute automation rules' do
      allow(conditions_filter_service).to receive(:perform).and_return(true)
      listener.kanban_task_created(event)
      expect(FazerAi::AutomationRules::KanbanActionService).not_to have_received(:new)
    end
  end

  describe '#kanban_task_created' do
    let!(:automation_rule) do
      create(:automation_rule,
             account: account,
             event_name: 'kanban_task_created',
             conditions: [{ attribute_key: 'kanban_board_id', filter_operator: 'equal_to', values: [board.id], query_operator: nil }],
             actions: [{ action_name: 'assign_agent', action_params: [agent.id] }])
    end

    let(:event) do
      Events::Base.new('kanban_task_created', Time.zone.now, { task: task })
    end

    context 'when matching rules are present' do
      it 'calls KanbanActionService if conditions match' do
        allow(conditions_filter_service).to receive(:perform).and_return(true)
        listener.kanban_task_created(event)
        expect(FazerAi::AutomationRules::KanbanActionService).to have_received(:new).with(automation_rule, account, task)
      end

      it 'does not call KanbanActionService if conditions do not match' do
        allow(conditions_filter_service).to receive(:perform).and_return(false)
        listener.kanban_task_created(event)
        expect(FazerAi::AutomationRules::KanbanActionService).not_to have_received(:new)
      end

      it 'calls KanbanActionService for each rule when multiple rules are present' do
        create(:automation_rule, event_name: 'kanban_task_created', account: account)
        allow(conditions_filter_service).to receive(:perform).and_return(true)
        listener.kanban_task_created(event)
        expect(FazerAi::AutomationRules::KanbanActionService).to have_received(:new).twice
      end

      it 'does not call KanbanActionService if performed by automation' do
        event.data[:performed_by] = automation_rule
        allow(conditions_filter_service).to receive(:perform).and_return(true)
        listener.kanban_task_created(event)
        expect(FazerAi::AutomationRules::KanbanActionService).not_to have_received(:new)
      end
    end
  end

  describe '#kanban_task_updated' do
    let!(:automation_rule) do
      create(:automation_rule,
             account: account,
             event_name: 'kanban_task_updated',
             conditions: [{ attribute_key: 'kanban_board_id', filter_operator: 'equal_to', values: [board.id], query_operator: nil }],
             actions: [{ action_name: 'send_webhook_event', action_params: ['https://example.com/webhook'] }])
    end

    let(:event) do
      Events::Base.new('kanban_task_updated', Time.zone.now, { task: task, changed_attributes: { priority: [nil, 'urgent'] } })
    end

    context 'when matching rules are present' do
      it 'calls KanbanActionService if conditions match' do
        allow(conditions_filter_service).to receive(:perform).and_return(true)
        listener.kanban_task_updated(event)
        expect(FazerAi::AutomationRules::KanbanActionService).to have_received(:new).with(automation_rule, account, task)
      end

      it 'does not call KanbanActionService if conditions do not match' do
        allow(conditions_filter_service).to receive(:perform).and_return(false)
        listener.kanban_task_updated(event)
        expect(FazerAi::AutomationRules::KanbanActionService).not_to have_received(:new)
      end

      it 'does not call KanbanActionService if performed by automation' do
        event.data[:performed_by] = automation_rule
        allow(conditions_filter_service).to receive(:perform).and_return(true)
        listener.kanban_task_updated(event)
        expect(FazerAi::AutomationRules::KanbanActionService).not_to have_received(:new)
      end
    end
  end

  describe '#kanban_task_completed' do
    let!(:automation_rule) do
      create(:automation_rule,
             account: account,
             event_name: 'kanban_task_completed',
             conditions: [{ attribute_key: 'kanban_board_id', filter_operator: 'equal_to', values: [board.id], query_operator: nil }],
             actions: [{ action_name: 'send_webhook_event', action_params: ['https://example.com/webhook'] }])
    end

    let(:event) do
      Events::Base.new('kanban_task_completed', Time.zone.now, { task: task, changed_attributes: { board_step_id: [1, 2] } })
    end

    context 'when matching rules are present' do
      it 'calls KanbanActionService if conditions match' do
        allow(conditions_filter_service).to receive(:perform).and_return(true)
        listener.kanban_task_completed(event)
        expect(FazerAi::AutomationRules::KanbanActionService).to have_received(:new).with(automation_rule, account, task)
      end

      it 'does not call KanbanActionService if conditions do not match' do
        allow(conditions_filter_service).to receive(:perform).and_return(false)
        listener.kanban_task_completed(event)
        expect(FazerAi::AutomationRules::KanbanActionService).not_to have_received(:new)
      end
    end
  end

  describe '#kanban_task_cancelled' do
    let!(:automation_rule) do
      create(:automation_rule,
             account: account,
             event_name: 'kanban_task_cancelled',
             conditions: [{ attribute_key: 'kanban_board_id', filter_operator: 'equal_to', values: [board.id], query_operator: nil }],
             actions: [{ action_name: 'send_webhook_event', action_params: ['https://example.com/webhook'] }])
    end

    let(:event) do
      Events::Base.new('kanban_task_cancelled', Time.zone.now, { task: task, changed_attributes: { board_step_id: [1, 3] } })
    end

    context 'when matching rules are present' do
      it 'calls KanbanActionService if conditions match' do
        allow(conditions_filter_service).to receive(:perform).and_return(true)
        listener.kanban_task_cancelled(event)
        expect(FazerAi::AutomationRules::KanbanActionService).to have_received(:new).with(automation_rule, account, task)
      end

      it 'does not call KanbanActionService if conditions do not match' do
        allow(conditions_filter_service).to receive(:perform).and_return(false)
        listener.kanban_task_cancelled(event)
        expect(FazerAi::AutomationRules::KanbanActionService).not_to have_received(:new)
      end
    end
  end
end
